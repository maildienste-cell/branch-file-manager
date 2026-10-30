import AppKit
import Speech
import AVFoundation

// Interpret selection/count separately from model-generated file filters.
struct BottiSelectionRequest {
    let limit: Int?
    let recursive: Bool
    let largest: Bool
    init(_ text: String) {
        let t = text.lowercased()
        recursive = t.contains("unterordner") && !t.contains("ohne unterordner")
        largest = t.contains("größt") || t.contains("groesst")
        let number = "(\\d+|eine|einen|eins|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn)"
        let patterns = [number + "\\s+(?:größten?\\s+|groessten?\\s+|neuesten?\\s+)?dateien?", "(?:größten?|groessten?|neuesten?)\\s+" + number + "\\b"]
        let words = ["eine":1,"einen":1,"eins":1,"zwei":2,"drei":3,"vier":4,"fünf":5,"sechs":6,"sieben":7,"acht":8,"neun":9,"zehn":10]
        var found: Int?
        for pattern in patterns {
            if let re = try? NSRegularExpression(pattern:pattern), let m = re.firstMatch(in:t,range:NSRange(t.startIndex...,in:t)), let r = Range(m.range(at:1),in:t) { found = Int(t[r]) ?? words[String(t[r])]; break }
        }
        limit = found
    }
}

final class BottiPrompt: NSTextView {
    var submit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { submit?(); return }
        super.keyDown(with:event)
    }
}

final class FileChat: NSObject {
    weak var app: AppDelegate?
    let view = BranchBackground()
    private let content = NSStackView()
    private let prompt = BottiPrompt()
    private let answer = NSTextView()
    private let scopeLabel = NSTextField(labelWithString:"")
    private let send = NSButton(title:"Senden",target:nil,action:nil)
    private let microphone = NSButton(title:"",target:nil,action:nil)
    private let cancel = NSButton(title:"Stoppen",target:nil,action:nil)
    private let provider = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let privacy = NSTextField(labelWithString:"")
    private let options = NSStackView()
    private var drawerHeight: NSLayoutConstraint!
    private var task: Task<Void,Never>?
    private var statusTask: Task<Void,Never>?
    private var token = StopRequest()
    private var details = ""
    private var engine: AVAudioEngine?
    private var speechTask: SFSpeechRecognitionTask?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var microphoneTask: Task<Void,Never>?
    private var recordingID = UUID()
    private var speechTimer: Timer?
    private var recognizer: SFSpeechRecognizer?
    private var recording = false
    private var targetPane: BrowserPane { app!.activePane }
    var isPresented: Bool { !content.isHidden }

    init(app: AppDelegate) {
        self.app = app
        super.init()
        view.wantsLayer = true; view.layer?.cornerRadius = 12
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(content)
        drawerHeight = view.heightAnchor.constraint(equalToConstant:0); drawerHeight.isActive = true
        let title = NSTextField(labelWithString:"Botti"); title.font = .systemFont(ofSize:15,weight:.bold); title.textColor = BranchStyle.mint
        scopeLabel.font = .systemFont(ofSize:11); scopeLabel.textColor = BranchStyle.muted; scopeLabel.lineBreakMode = .byTruncatingMiddle
        let settingsButton = NSButton(image:NSImage(systemSymbolName:"slider.horizontal.3",accessibilityDescription:"Botti-Einstellungen")!,target:self,action:#selector(toggleOptions)); settingsButton.bezelStyle = .rounded
        let close = NSButton(image:NSImage(systemSymbolName:"xmark",accessibilityDescription:"Botti schließen")!,target:self,action:#selector(hide)); close.bezelStyle = .rounded
        let header = NSStackView(views:[title,scopeLabel,NSView(),settingsButton,close]); header.spacing = 10
        provider.addItems(withTitles:["Qwen 3.5 · 4B","Apple Intelligence","Ohne KI"])
        provider.selectItem(at:LocalFileAI.provider == "ollama" ? 0 : LocalFileAI.provider == "none" ? 2 : 1)
        provider.target = self; provider.action = #selector(changeProvider)
        mode.addItems(withTitles:["Dateien finden / markieren","Ausgewählte Datei befragen"])
        privacy.font = .systemFont(ofSize:10); privacy.lineBreakMode = .byTruncatingTail
        let open = NSButton(title:"Ollama öffnen",target:self,action:#selector(startOllama)); open.bezelStyle = .rounded
        options.setViews([provider,mode,open,privacy],in:.leading); options.spacing = 8; options.isHidden = true
        answer.isEditable = false; answer.isSelectable = true; answer.drawsBackground = false; answer.font = .systemFont(ofSize:12); answer.textColor = BranchStyle.text
        answer.textContainerInset = NSSize(width:4,height:4); answer.textContainer?.widthTracksTextView = true; answer.autoresizingMask = [.width]
        let response = NSScrollView(); response.documentView = answer; response.hasVerticalScroller = true; response.drawsBackground = false
        response.heightAnchor.constraint(equalToConstant:48).isActive = true
        prompt.isRichText = false; prompt.font = .systemFont(ofSize:16); prompt.textColor = NSColor(srgbRed:0.08,green:0.13,blue:0.22,alpha:1)
        prompt.backgroundColor = NSColor(srgbRed:0.94,green:0.97,blue:1,alpha:1); prompt.insertionPointColor = .systemBlue
        prompt.textContainerInset = NSSize(width:14,height:12); prompt.isHorizontallyResizable = false; prompt.autoresizingMask = [.width]; prompt.textContainer?.widthTracksTextView = true
        prompt.setAccessibilityLabel("Deine Nachricht an Botti")
        prompt.submit = { [weak self] in self?.ask() }
        let input = NSScrollView(); input.documentView = prompt; input.hasVerticalScroller = true; input.wantsLayer = true; input.layer?.cornerRadius = 10; input.layer?.borderWidth = 2; input.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        input.heightAnchor.constraint(equalToConstant:96).isActive = true
        microphone.image = NSImage(systemSymbolName:"mic.fill",accessibilityDescription:"Spracheingabe starten"); microphone.bezelStyle = .rounded; microphone.target = self; microphone.action = #selector(toggleMicrophone); microphone.toolTip = "Deutsch diktieren – erst Senden führt die Anfrage aus"
        send.bezelStyle = .rounded; send.target = self; send.action = #selector(ask); send.contentTintColor = .systemBlue
        cancel.bezelStyle = .rounded; cancel.target = self; cancel.action = #selector(stopSearch); cancel.isHidden = true
        let hint = NSTextField(labelWithString:"Nachricht eingeben oder diktieren · ⌘↵ senden"); hint.font = .systemFont(ofSize:11); hint.textColor = BranchStyle.muted
        let detail = NSButton(title:"Details",target:self,action:#selector(showDetails)); detail.bezelStyle = .rounded
        let actions = NSStackView(views:[microphone,hint,NSView(),detail,cancel,send]); actions.spacing = 8
        for row in [header,options,response,input,actions] { content.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:content.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([content.topAnchor.constraint(equalTo:view.topAnchor,constant:10),content.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:14),content.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-14)])
        content.isHidden = true
        answer.string = "Was möchtest du finden? Zum Beispiel: „Markiere die drei größten Dateien.“"
    }
    func present() {
        _ = app?.activePane // Remember the pane before focusing the input.
        content.isHidden = false; drawerHeight.constant = options.isHidden ? 256 : 292
        app?.updateSplitTitle()
        if let window = app?.window, window.frame.height < 700 { var f = window.frame; f.origin.y -= 700-f.height; f.size.height = 700; window.setFrame(f,display:true) }
        updateScope(); refreshModelStatus(); app?.window.makeFirstResponder(prompt)
    }
    @objc func hide() { stopSearch(); stopMicrophone(); content.isHidden = true; drawerHeight.constant = 0; app?.updateSplitTitle() }
    @objc private func toggleOptions() { options.isHidden.toggle(); drawerHeight.constant = options.isHidden ? 256 : 292; refreshModelStatus() }
    func selectionChanged(in pane: BrowserPane) {
        guard isPresented, task == nil else { return }
        let folder = Self.searchRoot(pane)
        scopeLabel.stringValue = "In: " + label(folder); scopeLabel.toolTip = folder.path
    }
    private func updateScope() {
        guard let app else { return }; let pane = app.activePane
        let folder = Self.searchRoot(pane)
        scopeLabel.stringValue = "In: " + label(folder); scopeLabel.toolTip = folder.path
    }
    static func searchRoot(_ pane: BrowserPane) -> URL {
        pane.selected.count == 1 && isFolder(pane.selected[0]) ? pane.selected[0] : pane.current
    }
    private func refreshModelStatus() {
        statusTask?.cancel(); statusTask = Task { @MainActor in
            let value = await LocalFileAI.status(); guard !Task.isCancelled else { return }; privacy.stringValue = value; privacy.toolTip = value
        }
    }
    @objc private func changeProvider() { LocalFileAI.provider = ["ollama","apple","none"][provider.indexOfSelectedItem]; refreshModelStatus() }
    @objc private func startOllama() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.electron.ollama") else { answer.string = "Bitte installiere oder öffne Ollama."; return }
        NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration()) { _,_ in Task { @MainActor in self.refreshModelStatus() } }
    }
    @objc private func showDetails() {
        let a = NSAlert(); a.messageText = "Botti · Details"; a.informativeText = details.isEmpty ? "Botti sucht nach Dateinamen, Typ, Größe und Änderungsdatum. Ein ausgewählter Ordner hat Vorrang. Ohne ausdrücklichen Wunsch werden Unterordner nicht durchsucht. Ergebnisse erscheinen direkt in der Dateiansicht. Blau bedeutet ausgewählt, nicht dauerhaft mit einem Farb-Tag versehen. Dokumentfragen nutzen maximal 8 PDF-Seiten bzw. 8.000 Zeichen. Keine automatische Dateiänderung." : details
        if let window = app?.window { a.beginSheetModal(for:window) }
    }
    private func busy(_ value: Bool) { send.isEnabled = !value; provider.isEnabled = !value; mode.isEnabled = !value; prompt.isEditable = !value; microphone.isEnabled = !value; cancel.isHidden = !value; RobotState.shared.searching = value }
    @objc private func stopSearch() { token.request(); task?.cancel() }
    @objc private func ask() {
        guard task == nil, let app else { return }
        stopMicrophone()
        let question = prompt.string.trimmingCharacters(in:.whitespacesAndNewlines); guard !question.isEmpty else { return }
        let pane = app.activePane, folder = Self.searchRoot(app.activePane), selected = app.activePane.selected.first
        let document = mode.indexOfSelectedItem == 1 || question.lowercased().contains("zusammenfass")
        let request = BottiSelectionRequest(question), model = LocalFileAI.providerName
        updateScope(); busy(true); answer.string = "Ich schaue nach …"; token = StopRequest(); let stop = token
        let originalFolder = pane.current
        task = Task { @MainActor in
            defer { self.busy(false); self.task = nil }
            do {
                if document {
                    guard let selected, !isFolder(selected) else { throw transferError("Markiere zuerst eine Textdatei oder ein PDF.") }
                    let text = try await Task.detached(priority:.userInitiated) { try FileSearch.excerpt(selected) }.value
                    try Task.checkCancellation()
                    let value = try await LocalFileAI.summarize(text,name:selected.lastPathComponent,question:question)
                    try Task.checkCancellation(); answer.string = value
                    details = "Modell: \(model)\nQuelle: \(selected.path)\nTextauszug: maximal 8 Seiten / 8.000 Zeichen. Antworten können Fehler enthalten."
                } else {
                    if let limit = request.limit, limit < 1 || limit > 200 { throw transferError("Bitte wähle zwischen 1 und 200 Dateien auf einmal aus.") }
                    var query = await LocalFileAI.query(question)
                    if request.largest { query.order = "largest" }
                    try Task.checkCancellation()
                    let frozenQuery = query
                    let result = await Task.detached(priority:.userInitiated) { FileSearch.search(frozenQuery,root:folder,stop:stop,recursive:request.recursive) }.value
                    try Task.checkCancellation()
                    guard pane.current == originalFolder else { throw transferError("Du hast den Ordner gewechselt. Bitte starte die Suche dort erneut.") }
                    let hits = Array(result.hits.prefix(request.limit ?? 200))
                    if query.intent != "count" && query.intent != "totalSize" { Self.show(hits,in:pane,root:folder,recursive:request.recursive,order:query.order); app.window.makeFirstResponder(pane.table) }
                    let incomplete = result.partial || result.inaccessible > 0
                    if query.intent == "count" { answer.string = "\(result.count) Treffer in „\(label(folder))“." }
                    else if query.intent == "totalSize" { answer.string = "\(result.count) Dateien · \(ByteCountFormatter.string(fromByteCount:result.totalBytes,countStyle:.file))." }
                    else { answer.string = hits.isEmpty ? "Keine passenden Dateien in „\(label(folder))“ gefunden." : "\(hits.count) \(request.largest ? "größte " : "")Dateien in „\(label(folder))“ blau ausgewählt." }
                    if incomplete { answer.string += " Die Suche ist unvollständig; siehe Details." }
                    else if request.limit == nil && result.count > hits.count && query.intent == "find" { answer.string += " Angezeigt: \(hits.count) von \(result.count)." }
                    if !query.usedAI { answer.string += " Ohne KI gesucht; Filter unter Details prüfen." }
                    details = "Frage: \(question)\nSuchbereich: \(folder.path)\nUnterordner: \(request.recursive ? "ja" : "nein")\nName: \(query.terms.joined(separator:", "))\nTyp: \(query.kind) · Tage: \(query.days) · Mindestgröße: \(query.minimumBytes) Bytes\nGefunden: \(result.count), angezeigt: \(hits.count)\nNicht lesbar: \(result.inaccessible), Zeit-/Dateilimit erreicht: \(result.partial)\n\(query.usedAI ? model : "Stichwortsuche")\nVersteckte Dateien, Linkziele und App-Paketinhalte werden nicht durchsucht. Keine dauerhaften Farb-Tags geändert."
                }
                RobotState.shared.celebrationUntil = Date(timeIntervalSinceNow:4)
            } catch { answer.string = Task.isCancelled ? "Gestoppt." : error.localizedDescription }
        }
    }
    @MainActor func testCommand(_ text:String) async {
        precondition(testingUI)
        prompt.string = text; ask(); await task?.value
    }
    var testAnswer: String { answer.string }
    static func show(_ hits:[FileHit],in pane:BrowserPane,root:URL,recursive:Bool,order:String) {
        pane.search.stringValue = ""; pane.navigate(root)
        pane.table.sortDescriptors = [NSSortDescriptor(key:order == "largest" ? "size" : order == "newest" ? "date" : "name",ascending:order == "name")]
        if recursive { pane.recursiveResults = hits.map(\.url); pane.filter() }
        let urls = Set(hits.map { $0.url.standardizedFileURL })
        let rows = IndexSet(pane.visibleFiles.indices.filter { urls.contains(pane.visibleFiles[$0].standardizedFileURL) })
        pane.table.selectRowIndexes(rows,byExtendingSelection:false)
        if let first = rows.first { pane.table.scrollRowToVisible(first) }
        pane.status.stringValue = "\(rows.count) ausgewählt" + (recursive ? " · Botti-Treffer inkl. Unterordner · F5 zeigt den Ordner" : "")
    }

    @objc private func toggleMicrophone() {
        if recording || microphoneTask != nil { stopMicrophone(); return }
        let id = UUID(); recordingID = id
        microphoneTask = Task { @MainActor in
            defer { if self.recordingID == id { self.microphoneTask = nil } }
            let authorized = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning:$0 == .authorized) } }
            guard !Task.isCancelled, recordingID == id else { return }
            guard authorized else { answer.string = "Bitte erlaube Branch die Spracherkennung in den Systemeinstellungen unter Datenschutz & Sicherheit."; return }
            let allowed = await AVCaptureDevice.requestAccess(for:.audio)
            guard !Task.isCancelled, recordingID == id else { return }
            guard allowed else { answer.string = "Bitte erlaube Branch den Mikrofonzugriff in Datenschutz & Sicherheit."; return }
            guard let recognizer = SFSpeechRecognizer(locale:Locale(identifier:"de-DE")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { answer.string = "Deutsche Offline-Spracherkennung ist auf diesem Mac gerade nicht verfügbar. Du kannst weiterhin tippen."; return }
            let audio = AVAudioEngine(), request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            let input = audio.inputNode, format = audio.inputNode.outputFormat(forBus:0)
            guard format.sampleRate > 0, format.channelCount > 0 else { answer.string = "Kein Mikrofon verfügbar."; return }
            let prefix = prompt.string.isEmpty ? "" : prompt.string + "\n"
            input.installTap(onBus:0,bufferSize:1024,format:format) { buffer,_ in request.append(buffer) }
            engine = audio; speechRequest = request; self.recognizer = recognizer
            speechTask = recognizer.recognitionTask(with:request) { [weak self] result,error in
                DispatchQueue.main.async {
                    guard let self, self.recordingID == id else { return }
                    if let result { self.prompt.string = prefix + result.bestTranscription.formattedString }
                    if result?.isFinal == true || error != nil { self.stopMicrophone(); self.answer.string = error == nil ? "Text übernommen. Prüfe ihn und drücke Senden." : "Diktat beendet. Prüfe den Text; bei Bedarf erneut diktieren." }
                }
            }
            do {
                audio.prepare(); try audio.start(); recording = true
                microphone.image = NSImage(systemSymbolName:"stop.circle.fill",accessibilityDescription:"Diktat stoppen"); microphone.contentTintColor = .systemRed
                answer.string = "Ich höre zu … Zum Beenden erneut auf das Mikrofon klicken."
                speechTimer = Timer(timeInterval:55,target:self,selector:#selector(dictationExpired),userInfo:nil,repeats:false)
                RunLoop.main.add(speechTimer!,forMode:.common)
            } catch { stopMicrophone(); answer.string = "Das Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)" }
        }
    }
    @objc private func dictationExpired() { stopMicrophone() }
    private func stopMicrophone() {
        recordingID = UUID(); microphoneTask?.cancel(); microphoneTask = nil; speechTimer?.invalidate(); speechTimer = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus:0); engine = nil
        speechRequest?.endAudio(); speechTask?.cancel(); speechTask = nil; speechRequest = nil; recognizer = nil
        if recording { answer.string = "Text übernommen. Prüfe ihn und drücke Senden." }
        recording = false; microphone.image = NSImage(systemSymbolName:"mic.fill",accessibilityDescription:"Spracheingabe starten"); microphone.contentTintColor = nil
    }
}
