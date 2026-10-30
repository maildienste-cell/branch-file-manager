import Foundation
import Darwin

final class CopyMeter {
    var previous: Int64 = 0
    var currentFile = ""
    let report: (Int64) -> Void
    let fileFinished: (String) -> Void
    var finished = Set<String>()
    init(_ report: @escaping (Int64) -> Void, fileFinished: @escaping (String) -> Void) { self.report = report; self.fileFinished = fileFinished }
}
private let copyProgress: copyfile_callback_t = { what, stage, state, source, _, context in
    guard let context, let state else { return COPYFILE_CONTINUE }
    let meter = Unmanaged<CopyMeter>.fromOpaque(context).takeUnretainedValue()
    if what == COPYFILE_COPY_DATA {
        let path = source.map { String(cString:$0) } ?? ""
        if path != meter.currentFile || stage == COPYFILE_START { meter.previous = 0; meter.currentFile = path }
        if stage == COPYFILE_PROGRESS || stage == COPYFILE_FINISH {
            var bytes: off_t = 0
            if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &bytes) == 0 {
                let delta = max(0, Int64(bytes)-meter.previous); meter.previous = Int64(bytes)
                if delta > 0 { meter.report(delta) }
            }
        }
    }
    if stage == COPYFILE_FINISH && (what == COPYFILE_COPY_DATA || what == COPYFILE_RECURSE_FILE), let source {
        let path = String(cString:source)
        if meter.finished.insert(path).inserted { meter.fileFinished(path) }
    }
    return COPYFILE_CONTINUE
}
func copyWithProgress(_ source: URL, _ target: URL, fileFinished: @escaping (String) -> Void = { _ in }, report: @escaping (Int64) -> Void) throws {
    guard let state = copyfile_state_alloc() else { throw transferError("Der Kopiervorgang konnte nicht vorbereitet werden.") }
    defer { copyfile_state_free(state) }
    let meter = CopyMeter(report, fileFinished:fileFinished)
    let callback = unsafeBitCast(copyProgress, to: UnsafeRawPointer.self)
    copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), callback)
    copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(meter).toOpaque())
    let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
    let result = withExtendedLifetime(meter) { copyfile(source.path, target.path, state, flags) }
    if result != 0 { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno),userInfo:[NSLocalizedDescriptionKey:"\(source.lastPathComponent): \(String(cString:strerror(errno)))"]) }
}
final class TransferSpeed {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var lastBytes: Int64 = 0
    private var lastTime = ProcessInfo.processInfo.systemUptime
    func add(_ count: Int64) { lock.lock(); bytes += count; lock.unlock() }
    func sample() -> Double? {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now-lastTime
        guard elapsed >= 0.25 else { return nil }
        let rate = Double(bytes-lastBytes)/elapsed; lastBytes = bytes; lastTime = now
        return rate
    }
    static func label(_ rate: Double) -> String { ByteCountFormatter.string(fromByteCount:Int64(max(0,rate)),countStyle:.file) + "/s" }
}

// A single job includes files inside folders. Symlinks count once, without following them.
struct TransferInventory {
    var files: [String:Int64] = [:]
    var bytes: Int64 { files.values.reduce(0,+) }
    static func scan(_ root: URL, stop: StopRequest) throws -> TransferInventory {
        var result = TransferInventory()
        func include(_ url: URL) throws -> Bool {
            if stop.isRequested { throw CancellationError() }
            let a = try fm.attributesOfItem(atPath:url.path)
            let directory = (a[.type] as? FileAttributeType) == .typeDirectory
            if !directory { result.files[TransferEngine.canonical(url).path] = (a[.type] as? FileAttributeType) == .typeRegular ? (a[.size] as? NSNumber)?.int64Value ?? 0 : 0 }
            return directory
        }
        if try include(root) {
            var failure: Error?
            let e = fm.enumerator(at:root,includingPropertiesForKeys:nil,options:[],errorHandler: { _, error in failure = error; return false })
            while let url = e?.nextObject() as? URL { _ = try include(url) }
            if let failure { throw failure }
        }
        return result
    }
}
struct TransferSnapshot {
    let done: Int
    let total: Int
    let bytes: Int64
    let totalBytes: Int64
    let rate: Double
    let seconds: Double?
    var complete = false
    var fraction: Double { if complete { return 1 }; return totalBytes > 0 ? min(0.995,Double(bytes)/Double(totalBytes)) : (total > 0 ? min(0.995,Double(done)/Double(total)) : 0) }
    var remaining: String {
        guard let seconds else { return "Restzeit wird berechnet …" }
        if seconds < 1 { return "Wird abgeschlossen …" }
        if seconds < 60 { return "Noch ca. \(max(1,Int(ceil(seconds)))) Sek." }
        if seconds < 3600 { return "Noch ca. \(Int(ceil(seconds/60))) Min." }
        return "Noch ca. \(Int(seconds/3600)) Std. \(Int(seconds.truncatingRemainder(dividingBy:3600)/60)) Min."
    }
}
final class TransferJob {
    private let lock = NSLock()
    private var files: [String:Int64] = [:]
    private var finished = Set<String>()
    private var bytes: Int64 = 0
    private var previousBytes: Int64 = 0
    private var lastTime: Double = 0
    private var rate: Double = 0
    private var samples = 0
    private var started: Double = 0
    func prepare(_ inventories: [TransferInventory], now: Double = ProcessInfo.processInfo.systemUptime) {
        lock.lock(); defer { lock.unlock() }
        files = inventories.reduce(into:[:]) { $0.merge($1.files) { a,_ in a } }; started = now; lastTime = now
    }
    func add(_ n: Int64) { lock.lock(); bytes += n; lock.unlock() }
    func finish(_ path: String) { let key = TransferEngine.canonical(URL(fileURLWithPath:path)).path; lock.lock(); if files[key] != nil { finished.insert(key) }; lock.unlock() }
    func complete(_ inventory: TransferInventory, measured: Bool) {
        lock.lock(); defer { lock.unlock() }
        finished.formUnion(inventory.files.keys)
        if !measured { bytes += inventory.bytes }
    }
    func skip(_ inventory: TransferInventory) {
        lock.lock(); defer { lock.unlock() }
        for path in inventory.files.keys { files.removeValue(forKey:path) }
    }
    func resume(now: Double = ProcessInfo.processInfo.systemUptime) {
        lock.lock(); defer { lock.unlock() }
        previousBytes = bytes; lastTime = now; rate = 0; samples = 0; started = now
    }
    func snapshot(now: Double = ProcessInfo.processInfo.systemUptime) -> TransferSnapshot {
        lock.lock(); defer { lock.unlock() }
        let elapsed = now-lastTime
        if elapsed >= 0.25 {
            let instant = Double(max(0,bytes-previousBytes))/elapsed
            rate = samples == 0 ? instant : rate * 0.65 + instant * 0.35
            if instant == 0 { rate = 0 }
            samples += 1; previousBytes = bytes; lastTime = now
        }
        let total = files.values.reduce(0,+), remaining = max(0,total-bytes)
        let eta: Double? = samples >= 2 && now-started >= 1 && rate > 0 ? Double(remaining)/rate : nil
        return TransferSnapshot(done:finished.count,total:files.count,bytes:min(bytes,total),totalBytes:total,rate:rate,seconds:eta)
    }
}
