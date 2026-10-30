import AppKit

func transferError(_ message: String) -> NSError { NSError(domain: "BranchTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
enum ConflictChoice { case keepBoth, skip, replace, cancel }
struct ConflictDecision {
    let choice: ConflictChoice
    let remember: Bool
}
// Kept only by a single transfer job; a new job always asks again.
struct ConflictMemory {
    private var remembered: ConflictChoice?
    mutating func resolve(_ source: URL, _ target: URL, ask: () -> ConflictDecision) -> ConflictChoice {
        let sameFile = TransferEngine.canonical(source) == TransferEngine.canonical(target)
        if let remembered, !(sameFile && remembered == .replace) { return remembered }
        let decision = ask()
        if decision.remember && decision.choice != .cancel && !(sameFile && decision.choice == .replace) {
            remembered = decision.choice
        }
        return decision.choice
    }
}
struct UndoTransfer {
    let source: URL
    let target: URL
    let copied: Bool
    let replaced: URL?
}
struct TransferEngine {
    var bytesCopied: (Int64) -> Void = { _ in }
    var fileFinished: (String) -> Void = { _ in }
    var phase: (Bool) -> Void = { _ in }
    // Injectable trash destination lets tests cover recovery without touching the real Trash.
    var trash: (URL) throws -> URL = { url in
        var result: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw transferError("Der Papierkorb hat keinen Wiederherstellungspfad zurückgegeben.") }
        return result as URL
    }
    static func exists(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }
    static func canonical(_ url: URL) -> URL { url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).standardizedFileURL }
    static func sources(_ urls: [URL], to folder: URL) throws -> [URL] {
        guard isFolder(folder) else { throw transferError("Der Zielordner ist nicht erreichbar.") }
        var seen = Set<String>()
        let unique = urls.filter { seen.insert(canonical($0).path).inserted }
        let topLevel = unique.filter { item in !unique.contains { other in other != item && canonical(item).path.hasPrefix(canonical(other).path + "/") } }
        let destination = folder.resolvingSymlinksInPath().standardizedFileURL
        for source in topLevel {
            guard exists(source) else { throw transferError("Nicht gefunden: \(source.path)") }
            let resolved = source.resolvingSymlinksInPath().standardizedFileURL
            if resolved == destination || destination.path.hasPrefix(resolved.path + "/") { throw transferError("Ein Ordner kann nicht in sich selbst oder einen eigenen Unterordner übertragen werden.") }
        }
        return topLevel
    }
    static func unusedName(for url: URL) -> URL {
        let ext = url.pathExtension
        let name = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(name) (\(number))" + (ext.isEmpty ? "" : ".\(ext)"))
            if !exists(candidate) { return candidate }
            number += 1
        }
    }
    static func stamp(_ url: URL) -> String? {
        guard let a = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        return "\(a[.systemFileNumber] ?? "")|\(a[.modificationDate] ?? "")|\(a[.size] ?? "")"
    }
    func perform(_ source: URL, to folder: URL, copy: Bool, choice: ConflictChoice) throws -> UndoTransfer? {
        _ = try Self.sources([source], to: folder)
        var target = folder.appendingPathComponent(source.lastPathComponent)
        let conflict = Self.exists(target)
        if conflict {
            switch choice {
            case .skip, .cancel: return nil
            case .keepBoth: target = Self.unusedName(for: target)
            case .replace:
                guard Self.canonical(source) != Self.canonical(target) else { throw transferError("Eine Datei kann sich nicht selbst ersetzen. Wähle „Beide behalten“.") }
            }
        }
        let expectedTarget = Self.stamp(target)
        let staging = folder.appendingPathComponent(".branch-transfer-" + UUID().uuidString)
        let staged = staging.appendingPathComponent(source.lastPathComponent)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        var backup: URL?
        do {
            let sourceVolume = try fm.attributesOfItem(atPath: source.path)[.systemNumber] as? NSNumber
            let targetVolume = try fm.attributesOfItem(atPath: staging.path)[.systemNumber] as? NSNumber
            if copy || sourceVolume != targetVolume {
                phase(true)
                try copyWithProgress(source, staged, fileFinished:fileFinished, report: bytesCopied)
                if !copy { try fm.removeItem(at: source) }
            } else {
                phase(false)
                try fm.moveItem(at: source, to: staged)
            }
            guard Self.stamp(target) == expectedTarget else { throw transferError("Das Ziel wurde während der Übertragung verändert. Es wurde nichts überschrieben: \(target.path)") }
            if Self.exists(target) { backup = try trash(target) }
            try fm.moveItem(at: staged, to: target)
            try? fm.removeItem(at: staging)
            return UndoTransfer(source: source, target: target, copied: copy, replaced: backup)
        } catch {
            let originalError = error
            var recovery: [String] = []
            if let backup, Self.exists(backup) {
                if !Self.exists(target) { do { try fm.moveItem(at: backup, to: target) } catch { recovery.append("Bisheriges Ziel: \(backup.path)") } }
                else { recovery.append("Bisheriges Ziel: \(backup.path)") }
            }
            if Self.exists(staged) {
                if copy { try? fm.removeItem(at: staged) }
                else if !Self.exists(source) { do { try fm.moveItem(at: staged, to: source) } catch { recovery.append("Quelldatei gesichert unter: \(staged.path)") } }
                else { recovery.append("Quelldatei gesichert unter: \(staged.path)") }
            }
            if (try? fm.contentsOfDirectory(atPath: staging.path).isEmpty) == true { try? fm.removeItem(at: staging) }
            throw transferError(originalError.localizedDescription + (recovery.isEmpty ? "" : "\n\n" + recovery.joined(separator: "\n")))
        }
    }
    static func validateUndo(_ entries: [UndoTransfer]) throws {
        for entry in entries {
            guard exists(entry.target) else { throw transferError("Die übertragene Datei fehlt inzwischen: \(entry.target.path)") }
            if !entry.copied && exists(entry.source) { throw transferError("Am ursprünglichen Ort liegt inzwischen wieder eine Datei. Bitte benenne sie zuerst um: \(entry.source.path)") }
            if let old = entry.replaced, !exists(old) { throw transferError("Die ersetzte Datei befindet sich nicht mehr im Papierkorb. Rückgängig ist nicht möglich: \(entry.target.lastPathComponent)") }
        }
    }
    func undo(_ entry: UndoTransfer) throws {
        try Self.validateUndo([entry])
        // Copies go to Trash rather than being permanently deleted, including later edits.
        let movedTo: URL
        if entry.copied { movedTo = try trash(entry.target) }
        else { try fm.moveItem(at: entry.target, to: entry.source); movedTo = entry.source }
        do {
            if let old = entry.replaced { try fm.moveItem(at: old, to: entry.target) }
        } catch {
            do { try fm.moveItem(at: movedTo, to: entry.target) }
            catch { throw transferError("Wiederherstellung unterbrochen. Die Datei liegt hier: \(movedTo.path). Die bisherige Zieldatei bleibt im Papierkorb.") }
            throw error
        }
    }
}
final class StopRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    var isRequested: Bool { lock.lock(); defer { lock.unlock() }; return requested }
    func request() { lock.lock(); requested = true; lock.unlock() }
}
final class TransferCenter: NSObject {
    static let shared = TransferCenter()
    private(set) var busy = false
    private(set) var undoStack: [[UndoTransfer]] = []
    private var stop = StopRequest()
    private var job = TransferJob()
    private var paused = false
    private var prepared = false
    private var speedTimer: Timer?
    private var measuringBytes = false
    var onChange: (() -> Void)?
    let status = NSTextField(labelWithString: "Bereit · Leertaste für Vorschau")
    let progress = NSProgressIndicator()
    let stopButton = NSButton(title: "Stoppen", target: nil, action: nil)
    let undoButton = NSButton(title: "Übertragung rückgängig", target: nil, action: nil)
    lazy var bar: NSStackView = {
        status.font = .systemFont(ofSize: 11); status.textColor = BranchStyle.muted; status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        progress.widthAnchor.constraint(equalToConstant: 110).isActive = true; progress.isHidden = true
        stopButton.target = self; stopButton.action = #selector(stopAfterItem); stopButton.bezelStyle = .rounded; stopButton.isHidden = true
        stopButton.toolTip = "Stoppt nach dem aktuellen Objekt. Fertige Übertragungen bleiben erhalten und können rückgängig gemacht werden."
        undoButton.target = self; undoButton.action = #selector(undoLast); undoButton.bezelStyle = .rounded; undoButton.isEnabled = false; undoButton.toolTip = "Kopieren und Verschieben dieser Sitzung rückgängig machen. Der Verlauf endet beim Beenden der App."
        let row = NSStackView(views: [status, NSView(), progress, stopButton, undoButton]); row.spacing = 10
        return row
    }()
    func announce(_ text: String, done: Int, total: Int) {
        status.stringValue = text; progress.maxValue = Double(max(1,total)); progress.doubleValue = Double(done)
    }
    func setBusy(_ value: Bool) {
        RobotState.shared.transferring = value
        speedTimer?.invalidate(); speedTimer = nil
        if value {
            job = TransferJob(); prepared = false; paused = false; measuringBytes = false
            RobotState.shared.snapshot = nil; RobotState.shared.transferText = "Dateien werden gezählt …"
            speedTimer = Timer(timeInterval:0.4,repeats:true) { [weak self] _ in self?.updateOverview() }
            RunLoop.main.add(speedTimer!,forMode:.common)
        }
        busy = value; progress.isHidden = true; status.isHidden = value; stopButton.isHidden = !value; stopButton.isEnabled = value
        undoButton.isEnabled = !value && !undoStack.isEmpty; onChange?()
    }
    private func updateOverview() {
        guard prepared, !paused else { return }
        RobotState.shared.snapshot = job.snapshot()
        RobotState.shared.transferText = stop.isRequested ? "Stoppt nach diesem Objekt …" : (measuringBytes ? "" : "Intern verschieben …")
    }
    @objc func stopAfterItem() { stop.request(); stopButton.isEnabled = false; status.stringValue = "Stoppt nach dem aktuellen Objekt …" }
    func makeConflictAlert(_ source: URL, _ target: URL) -> NSAlert {
        let a = NSAlert(); a.messageText = "„\(target.lastPathComponent)“ ist schon vorhanden"
        a.informativeText = "Ziel: \(target.deletingLastPathComponent().path)\n\n„Beide behalten“ vergibt einen neuen Namen. „Ersetzen“ legt das bisherige Ziel im Papierkorb ab. Ordner werden vollständig ersetzt, nicht zusammengeführt."
        a.addButton(withTitle: "Beide behalten"); a.addButton(withTitle: "Überspringen"); a.addButton(withTitle: "Ersetzen"); a.addButton(withTitle: "Abbrechen")
        if TransferEngine.canonical(source) == TransferEngine.canonical(target) { a.buttons[2].isEnabled = false }
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Für weitere Konflikte dieser Übertragung merken"
        a.suppressionButton?.state = .off
        a.suppressionButton?.toolTip = "Gilt für die restlichen Namenskonflikte dieses Kopier- oder Verschiebevorgangs. Beim nächsten Vorgang wird erneut gefragt."
        return a
    }
    func conflict(_ source: URL, _ target: URL) -> ConflictDecision {
        let a = makeConflictAlert(source,target)
        let choice: ConflictChoice
        switch a.runModal().rawValue { case 1000: choice = .keepBoth; case 1001: choice = .skip; case 1002: choice = .replace; default: choice = .cancel }
        return ConflictDecision(choice:choice,remember:a.suppressionButton?.state == .on)
    }
    func start(_ urls: [URL], to target: URL, copy: Bool) {
        guard !busy, !urls.isEmpty else { return }
        let sources: [URL]
        do { sources = try TransferEngine.sources(urls, to: target) } catch { failure(error.localizedDescription); return }
        stop = StopRequest(); let token = stop
        setBusy(true); announce("\(copy ? "Kopieren" : "Verschieben"): 0 / \(sources.count) Objekte", done: 0, total: sources.count)
        DispatchQueue.global(qos: .userInitiated).async {
            let tracker = self.job
            var inventories: [TransferInventory] = []
            do { inventories = try sources.map { try TransferInventory.scan($0,stop:token) } }
            catch {
                DispatchQueue.main.async {
                    self.setBusy(false); RobotState.shared.finished(success:false)
                    self.status.stringValue = token.isRequested ? "Gestoppt" : "Dateien konnten nicht gezählt werden"
                    if !token.isRequested { failure(error.localizedDescription) }
                }; return
            }
            tracker.prepare(inventories)
            DispatchQueue.main.async { self.prepared = true; self.updateOverview() }
            var measured = false
            let engine = TransferEngine(bytesCopied: { tracker.add($0) }, fileFinished: { tracker.finish($0) }, phase: { copying in
                if measured != copying { tracker.resume() }
                measured = copying
                DispatchQueue.main.async { self.measuringBytes = copying; self.updateOverview() }
            })
            var conflictMemory = ConflictMemory()
            var records: [UndoTransfer] = []; var skippedFiles = 0; var completedFiles = 0; var message: String?
            for (index, source) in sources.enumerated() {
                if token.isRequested { break }
                var choice = ConflictChoice.keepBoth
                let destination = target.appendingPathComponent(source.lastPathComponent)
                if TransferEngine.exists(destination) {
                    choice = conflictMemory.resolve(source,destination) {
                        var decision = ConflictDecision(choice:.cancel,remember:false)
                        DispatchQueue.main.sync {
                            self.paused = true; RobotState.shared.transferText = "Warte auf deine Auswahl …"
                            decision = self.conflict(source, destination)
                            tracker.resume(); self.paused = false
                        }
                        return decision
                    }
                }
                if choice == .cancel { token.request(); break }
                if choice == .skip { skippedFiles += inventories[index].files.count; tracker.skip(inventories[index]); continue }
                do {
                    if let record = try engine.perform(source, to: target, copy: copy, choice: choice) {
                        records.append(record); tracker.complete(inventories[index],measured:measured); completedFiles += inventories[index].files.count
                    }
                } catch { message = error.localizedDescription; break }
                DispatchQueue.main.async { self.updateOverview() }
            }
            let finalFiles = completedFiles, finalSkippedFiles = skippedFiles
            let completed = records; let errorMessage = message
            DispatchQueue.main.async {
                if !completed.isEmpty { self.undoStack.append(completed) }
                var finalSnapshot = tracker.snapshot()
                finalSnapshot.complete = errorMessage == nil && !token.isRequested
                RobotState.shared.snapshot = finalSnapshot
                RobotState.shared.transferCelebrationUntil = Date(timeIntervalSinceNow:5)
                self.setBusy(false)
                RobotState.shared.finished(success: errorMessage == nil && !token.isRequested && !completed.isEmpty)
                self.status.stringValue = "\(finalFiles) Dateien übertragen · \(finalSkippedFiles) Dateien übersprungen" + (token.isRequested ? " · gestoppt" : "")
                NotificationCenter.default.post(name: changed, object: nil)
                if let errorMessage { failure(errorMessage + "\n\n\(completed.count) vorherige Übertragungen wurden abgeschlossen und können rückgängig gemacht werden.") }
            }
        }
    }
    @objc func undoLast() {
        guard !busy, let batch = undoStack.last else { return }
        do { try TransferEngine.validateUndo(batch) } catch { failure(error.localizedDescription); return }
        let alert = NSAlert(); alert.messageText = "Letzte Übertragung rückgängig machen?"
        alert.informativeText = "\(batch.count) Objekte. Verschobene Objekte kehren an ihren ursprünglichen Ort zurück. Kopien werden in den Papierkorb gelegt; ersetzte Originale werden daraus wiederhergestellt."
        alert.addButton(withTitle: "Rückgängig"); alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        stop = StopRequest(); let token = stop
        setBusy(true); status.isHidden = false; RobotState.shared.transferText = "Wiederherstellen …"; announce("Übertragung wird rückgängig gemacht …", done: 0, total: batch.count)
        DispatchQueue.global(qos: .userInitiated).async {
            let engine = TransferEngine(); var remaining = batch; var message: String?
            while let entry = remaining.last, !token.isRequested {
                do { try engine.undo(entry); remaining.removeLast() }
                catch { message = error.localizedDescription; break }
                let count = batch.count - remaining.count
                DispatchQueue.main.async { self.announce("\(count) / \(batch.count) wiederhergestellt", done: count, total: batch.count) }
            }
            let leftover = remaining; let errorMessage = message
            DispatchQueue.main.async {
                self.undoStack.removeLast(); if !leftover.isEmpty { self.undoStack.append(leftover) }
                self.setBusy(false); RobotState.shared.finished(success: errorMessage == nil && leftover.isEmpty); self.status.stringValue = "\(batch.count - leftover.count) Objekte wiederhergestellt"
                NotificationCenter.default.post(name: changed, object: nil)
                if let errorMessage { failure(errorMessage) }
            }
        }
    }
}
