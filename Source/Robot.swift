import AppKit

enum RobotMood { case idle, thinking, working, happy, concerned }
final class RobotState {
    static let shared = RobotState()
    var searching = false
    var transferring = false
    var snapshot: TransferSnapshot?
    var transferText = "Vorbereiten …"
    var transferCelebrationUntil = Date.distantPast
    var celebrationUntil = Date.distantPast
    var concernUntil = Date.distantPast
    var mood: RobotMood {
        if transferring { return .working }
        if searching { return .thinking }
        if Date() < concernUntil { return .concerned }
        if Date() < celebrationUntil { return .happy }
        return .idle
    }
    var showsBubble: Bool { transferring || searching || mood == .happy }
    var bubble: String {
        switch mood {
        case .working: return transferText
        case .thinking: return "Ich denke nach …"
        case .happy: return "Geschafft! ✨"
        case .concerned: return "Schauen wir genauer hin …"
        case .idle: return "Frag mich zu deinen Dateien"
        }
    }
    func finished(success: Bool) { transferring = false; if success { celebrationUntil = Date(timeIntervalSinceNow: 5) } else { concernUntil = Date(timeIntervalSinceNow: 5) } }
}

struct RobotPose {
    var x: CGFloat = 0
    var lift: CGFloat = 0
    var angle: CGFloat = 0
    var stride: CGFloat = 0
    var headTilt: CGFloat = 0
    static func at(_ time: Double, mood: RobotMood, reduceMotion: Bool) -> RobotPose {
        guard !reduceMotion else { return RobotPose() }
        var p = RobotPose()
        switch mood {
        case .idle, .concerned: break
        case .working:
            p.lift = CGFloat(sin(time*4))*0.8
            p.stride = CGFloat(sin(time*4))*3
        case .thinking:
            p.headTilt = CGFloat(sin(time*1.6))*6
        case .happy:
            p.lift = CGFloat(abs(sin(time*4)))*5
            p.stride = 5
        }
        return p
    }
}

final class RobotView: NSView {
    var previewTime: Double?
    var onClick: (() -> Void)?
    private var timer: Timer?
    private let started = Date()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Botti – dein Datei-Assistent. Klicken zum Chatten."
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("Botti, Datei-Chat öffnen")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    override func keyDown(with event: NSEvent) { if [36,49].contains(event.keyCode) { onClick?() } else { super.keyDown(with: event) } }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func viewDidMoveToWindow() {
        timer?.invalidate(); timer = nil
        guard window != nil else { return }
        timer = Timer(timeInterval: 1.0/24.0, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }; self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    deinit { timer?.invalidate() }
    override func draw(_ dirtyRect: NSRect) {
        let state = RobotState.shared, mood = state.mood
        let t = previewTime ?? Date().timeIntervalSince(started)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let pose = RobotPose.at(t, mood:mood, reduceMotion:reduce)
        func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }
        func line(_ points: [NSPoint], _ color: NSColor, width: CGFloat = 3) {
            let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
            if let first = points.first { path.move(to:first); points.dropFirst().forEach { path.line(to:$0) } }; color.setStroke(); path.stroke()
        }
        let compactBubble = bounds.height < 120 && state.showsBubble
        if compactBubble { NSGraphicsContext.saveGraphicsState(); let move = NSAffineTransform(); move.translateX(by:0,yBy:-84); move.concat() }
        if state.showsBubble {
        // A cloud silhouette and two detached thought dots lead to Botti's head.
        let cloud = NSBezierPath()
        cloud.move(to:NSPoint(x:25,y:92))
        cloud.curve(to:NSPoint(x:19,y:137),controlPoint1:NSPoint(x:0,y:94),controlPoint2:NSPoint(x:0,y:128))
        cloud.curve(to:NSPoint(x:67,y:165),controlPoint1:NSPoint(x:10,y:162),controlPoint2:NSPoint(x:42,y:177))
        cloud.curve(to:NSPoint(x:130,y:170),controlPoint1:NSPoint(x:80,y:182),controlPoint2:NSPoint(x:112,y:180))
        cloud.curve(to:NSPoint(x:199,y:170),controlPoint1:NSPoint(x:147,y:184),controlPoint2:NSPoint(x:181,y:184))
        cloud.curve(to:NSPoint(x:268,y:158),controlPoint1:NSPoint(x:224,y:182),controlPoint2:NSPoint(x:256,y:182))
        cloud.curve(to:NSPoint(x:284,y:99),controlPoint1:NSPoint(x:310,y:159),controlPoint2:NSPoint(x:310,y:103))
        cloud.curve(to:NSPoint(x:218,y:90),controlPoint1:NSPoint(x:267,y:82),controlPoint2:NSPoint(x:237,y:84))
        cloud.curve(to:NSPoint(x:143,y:90),controlPoint1:NSPoint(x:194,y:80),controlPoint2:NSPoint(x:164,y:80))
        cloud.curve(to:NSPoint(x:80,y:91),controlPoint1:NSPoint(x:121,y:81),controlPoint2:NSPoint(x:96,y:82))
        cloud.curve(to:NSPoint(x:25,y:92),controlPoint1:NSPoint(x:61,y:82),controlPoint2:NSPoint(x:42,y:84))
        cloud.close(); BranchStyle.selected.setFill(); cloud.fill()
        BranchStyle.mint.withAlphaComponent(0.5).setStroke(); cloud.lineWidth = 1; cloud.stroke()
        for dot in [NSRect(x:199,y:76,width:10,height:8),NSRect(x:183,y:72,width:5,height:4)] {
            BranchStyle.selected.setFill(); NSBezierPath(ovalIn:dot).fill()
        }
        func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, color: NSColor = BranchStyle.text, centered: Bool = false) {
            let style = NSMutableParagraphStyle(); style.alignment = centered ? .center : .left; style.lineBreakMode = .byTruncatingTail
            (value as NSString).draw(in:NSRect(x:x,y:y,width:width,height:size+5),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:size,weight:.medium),.foregroundColor:color,.paragraphStyle:style])
        }
        if state.transferring || (mood == .happy && Date() < state.transferCelebrationUntil), let summary = state.snapshot {
            let center = NSPoint(x:44,y:140)
            let ring = NSBezierPath(ovalIn:NSRect(x:27,y:123,width:34,height:34)); ring.lineWidth = 4
            BranchStyle.muted.withAlphaComponent(0.25).setStroke(); ring.stroke()
            if summary.fraction > 0 {
                let arc = NSBezierPath(); arc.lineWidth = 4; arc.lineCapStyle = .round
                arc.appendArc(withCenter:center,radius:17,startAngle:90,endAngle:90-CGFloat(summary.fraction)*360,clockwise:true)
                BranchStyle.mint.setStroke(); arc.stroke()
            }
            text("\(Int(summary.fraction*100))%",x:24,y:133,width:40,size:9,centered:true)
            text("\(summary.done) von \(summary.total) Dateien",x:74,y:143,width:206,size:13)
            text(summary.complete ? "Fertig! ✨" : (state.transferText.isEmpty ? TransferSpeed.label(summary.rate) : state.transferText),x:74,y:125,width:206,size:12,color:BranchStyle.mint)
            let amount = ByteCountFormatter.string(fromByteCount:summary.bytes,countStyle:.file) + " / " + ByteCountFormatter.string(fromByteCount:summary.totalBytes,countStyle:.file)
            text(amount,x:24,y:107,width:262,size:10,centered:true)
            text(summary.complete ? "Alles übertragen" : (state.transferText.isEmpty ? summary.remaining : (state.transferText == "Intern verschieben …" ? "Keine Kopier-Restzeit nötig" : "")),x:24,y:92,width:262,size:10,color:BranchStyle.muted,centered:true)
        } else {
            text(state.bubble,x:25,y:124,width:260,size:12,centered:true)
        }
        }
        if compactBubble { NSGraphicsContext.restoreGraphicsState(); return }
        // One flat, front-facing mascot. All large motion is tied to task state.
        let cx = bounds.midX
        let shell = NSColor(calibratedRed:0.95,green:0.96,blue:0.92,alpha:1)
        let orange = NSColor(calibratedRed:1,green:0.58,blue:0.23,alpha:1)
        let joint = NSColor(calibratedRed:0.30,green:0.39,blue:0.40,alpha:1)
        NSGraphicsContext.saveGraphicsState()
        let bodyTransform = NSAffineTransform(); bodyTransform.translateX(by:0,yBy:pose.lift); bodyTransform.concat()
        // Flat duck feet, short legs and a compact friendly body.
        for offset: CGFloat in [-16,16] {
            rounded(NSRect(x:cx+offset-4,y:12,width:8,height:14),3,joint)
            rounded(NSRect(x:cx+offset-12,y:5,width:24,height:9),4,orange)
        }
        rounded(NSRect(x:cx-24,y:22,width:48,height:27),10,shell)
        for side: CGFloat in [-1,1] {
            let wing = NSBezierPath(); wing.lineWidth = 7; wing.lineCapStyle = .round
            wing.move(to:NSPoint(x:cx+side*23,y:41))
            let action = mood == .happy ? CGFloat(10) : side*pose.stride
            wing.line(to:NSPoint(x:cx+side*32,y:31+action))
            shell.setStroke(); wing.stroke()
        }
        rounded(NSRect(x:cx-10,y:29,width:20,height:10),5,BranchStyle.mint)
        line([NSPoint(x:cx-4,y:34),NSPoint(x:cx,y:31),NSPoint(x:cx+5,y:36)],NSColor(srgbRed:0.08,green:0.14,blue:0.19,alpha:1),width:1.5)
        rounded(NSRect(x:cx-5,y:46,width:10,height:8),3,joint)
        NSGraphicsContext.saveGraphicsState()
        let head = NSAffineTransform(); head.translateX(by:cx,yBy:58); head.rotate(byDegrees:pose.headTilt); head.translateX(by:-cx,yBy:-58); head.concat()
        rounded(NSRect(x:cx-35,y:47,width:70,height:35),12,shell)
        rounded(NSRect(x:cx-30,y:51,width:60,height:27),10,orange)
        rounded(NSRect(x:cx-26,y:54,width:52,height:22),8,NSColor(srgbRed:0.08,green:0.14,blue:0.19,alpha:1))
        let blink = !reduce && t.truncatingRemainder(dividingBy:4.5) > 4.30
        for side: CGFloat in [-1,1] {
            let x = cx+side*12
            if blink {
                line([NSPoint(x:x-4,y:65),NSPoint(x:x+4,y:65)],BranchStyle.mint,width:2.5)
            } else if mood == .happy {
                line([NSPoint(x:x-4,y:65),NSPoint(x:x,y:69),NSPoint(x:x+4,y:65)],BranchStyle.mint,width:2.5)
            } else if mood == .working {
                line([NSPoint(x:x-4,y:68+side*2),NSPoint(x:x+4,y:68-side*2)],BranchStyle.mint,width:3)
            } else {
                let look: CGFloat = mood == .thinking ? -2 : 0
                rounded(NSRect(x:x-3+look,y:63,width:6,height:mood == .concerned ? 6 : 9),3,BranchStyle.mint)
            }
        }
        // A small duck beak doubles as the smiling mouth.
        rounded(NSRect(x:cx-12,y:47,width:24,height:10),5,orange)
        let smile = NSBezierPath(); smile.lineWidth = 1.6; smile.lineCapStyle = .round
        smile.move(to:NSPoint(x:cx-6,y:53))
        let curve: CGFloat = mood == .working ? 51 : (mood == .concerned ? 56 : 47)
        smile.curve(to:NSPoint(x:cx+6,y:53),controlPoint1:NSPoint(x:cx-3,y:curve),controlPoint2:NSPoint(x:cx+3,y:curve))
        NSColor(srgbRed:0.08,green:0.14,blue:0.19,alpha:1).setStroke(); smile.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }
}
