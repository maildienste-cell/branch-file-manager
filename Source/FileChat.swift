import AppKit

final class FileChat: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    weak var app: AppDelegate?
    private let transcript = NSTextView()
    private let prompt = NSTextField()
    private let send = NSButton(title:"Senden",target:nil,action:nil)
    private let cancel = NSButton(title:"Stoppen",target:nil,action:nil)
    private let scope = NSPopUpButton()
    private let scopeLabel = NSTextField(labelWithString:"")
    private let results = NSTableView()
    private var hits: [FileHit] = []
    private var customRoot: URL?
    private var task: Task<Void,Never>?
    private var token = StopRequest()
    private var lastQuestion = ""
    init(app: AppDelegate) {
        self.app = app
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:620,height:680),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        panel.title = "Botti · Dein lokaler Datei-Assistent"; panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width:520,height:520)
        super.init(window:panel)
        let root = BranchBackground(); panel.contentView = root
        let privacy = NSTextField(labelWithString:LocalFileAI.available ? "Lokale KI · keine Datei-Uploads" : "Lokale Dateisuche · KI derzeit nicht verfügbar")
        privacy.font = .systemFont(ofSize:11,weight:.medium); privacy.textColor = BranchStyle.mint
        scope.addItems(withTitles:["Aktueller Ordner","Benutzerordner","Ordner wählen …"]); scope.target = self; scope.action = #selector(changeScope)
        scopeLabel.font = .systemFont(ofSize:10); scopeLabel.textColor = BranchStyle.muted; scopeLabel.lineBreakMode = .byTruncatingMiddle
        let top = NSStackView(views:[privacy,NSView(),scope]); top.spacing = 10
        transcript.isEditable = false; transcript.isSelectable = true; transcript.drawsBackground = false; transcript.textContainerInset = NSSize(width:10,height:10)
        transcript.isHorizontallyResizable = false; transcript.autoresizingMask = [.width]; transcript.textContainer?.widthTracksTextView = true
        let chatScroll = NSScrollView(); chatScroll.documentView = transcript; chatScroll.hasVerticalScroller = true; chatScroll.drawsBackground = false
        for (id,title,width) in [("name","Datei",180.0),("size","Größe",85.0),("date","Geändert",95.0)] {
            let c = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; results.addTableColumn(c)
        }
        results.delegate = self; results.dataSource = self; results.rowHeight = 28; results.backgroundColor = BranchStyle.base
        results.target = self; results.doubleAction = #selector(reveal); results.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let resultScroll = NSScrollView(); resultScroll.documentView = results; resultScroll.hasVerticalScroller = true
        let revealButton = NSButton(title:"In Branch zeigen",target:self,action:#selector(reveal)); revealButton.bezelStyle = .rounded
        let previewButton = NSButton(title:"Vorschau",target:self,action:#selector(preview)); previewButton.bezelStyle = .rounded
        let summary = NSButton(title:"Auswahl zusammenfassen",target:self,action:#selector(summarizeSelection)); summary.bezelStyle = .rounded
        let actions = NSStackView(views:[revealButton,previewButton,NSView(),summary]); actions.spacing = 6
        prompt.placeholderString = "Zum Beispiel: Welche PDFs habe ich letzte Woche geändert?"; prompt.target = self; prompt.action = #selector(ask)
        prompt.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        send.target = self; send.action = #selector(ask); send.bezelStyle = .rounded
        cancel.target = self; cancel.action = #selector(stopSearch); cancel.bezelStyle = .rounded; cancel.isHidden = true
        let input = NSStackView(views:[prompt,send,cancel]); input.spacing = 8
        for v in [top,scopeLabel,chatScroll,resultScroll,actions,input] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo:root.topAnchor,constant:12),top.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:12),top.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-12),
            scopeLabel.topAnchor.constraint(equalTo:top.bottomAnchor,constant:4),scopeLabel.leadingAnchor.constraint(equalTo:top.leadingAnchor),scopeLabel.trailingAnchor.constraint(equalTo:top.trailingAnchor),
            chatScroll.topAnchor.constraint(equalTo:scopeLabel.bottomAnchor,constant:6),chatScroll.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:6),chatScroll.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-6),
            resultScroll.topAnchor.constraint(equalTo:chatScroll.bottomAnchor,constant:8),resultScroll.leadingAnchor.constraint(equalTo:top.leadingAnchor),resultScroll.trailingAnchor.constraint(equalTo:top.trailingAnchor),resultScroll.heightAnchor.constraint(equalToConstant:170),
            actions.topAnchor.constraint(equalTo:resultScroll.bottomAnchor,constant:8),actions.leadingAnchor.constraint(equalTo:top.leadingAnchor),actions.trailingAnchor.constraint(equalTo:top.trailingAnchor),
            input.topAnchor.constraint(equalTo:actions.bottomAnchor,constant:10),input.leadingAnchor.constraint(equalTo:top.leadingAnchor),input.trailingAnchor.constraint(equalTo:top.trailingAnchor),input.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-12)
        ])
        append("Botti", "Hallo! Ich finde Dateien nach Name, Typ, Größe und Änderungsdatum. Zum Beispiel: „Zeige meine größten PDFs“ oder „Wie viele Bilder liegen hier?“\n\nFür eine Zusammenfassung wähle eine Datei in Branch oder in den Treffern aus. Ich lese dann nur einen begrenzten Auszug dieser Datei. Die Suche verändert keine Dateien.")
        panel.center(); updateScope()
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() { updateScope(); showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(prompt) }
    private var root: URL { scope.indexOfSelectedItem == 1 ? fm.homeDirectoryForCurrentUser : (scope.indexOfSelectedItem == 2 ? customRoot ?? fm.homeDirectoryForCurrentUser : app?.activePane.current ?? fm.homeDirectoryForCurrentUser) }
    private var selectedURL: URL? { hits.indices.contains(results.selectedRow) ? hits[results.selectedRow].url : app?.activePane.selected.first }
    private func updateScope() { scopeLabel.stringValue = "Suchbereich: " + root.path; scopeLabel.toolTip = root.path }
    @objc private func changeScope() {
        if scope.indexOfSelectedItem == 2 { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; if p.runModal() == .OK { customRoot = p.url } else { scope.selectItem(at:0) } }
        updateScope()
    }
    private func append(_ who: String, _ text: String) {
        let value = NSMutableAttributedString(string:"\(who)\n",attributes:[.font:NSFont.systemFont(ofSize:12,weight:.bold),.foregroundColor:who == "Botti" ? BranchStyle.mint : BranchStyle.gold])
        value.append(NSAttributedString(string:text + "\n\n",attributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:BranchStyle.text]))
        transcript.textStorage?.append(value); transcript.scrollToEndOfDocument(nil)
    }
    private func busy(_ value: Bool) { send.isEnabled = !value; prompt.isEnabled = !value; scope.isEnabled = !value; cancel.isHidden = !value; RobotState.shared.searching = value }
    @objc private func stopSearch() { token.request(); task?.cancel() }
    @objc private func summarizeSelection() { prompt.stringValue = "Fasse die ausgewählte Datei zusammen."; ask() }
    @objc private func ask() {
        guard task == nil else { return }
        let question = prompt.stringValue.trimmingCharacters(in:.whitespacesAndNewlines); guard !question.isEmpty else { return }
        let folder = root, selected = selectedURL
        updateScope(); prompt.stringValue = ""; append("Du",question); busy(true); token = StopRequest(); let stop = token
        let previous = lastQuestion
        task = Task { @MainActor in
            defer { self.busy(false); self.task = nil }
            let summaryRequested = question.lowercased().contains("zusammenfass") || question.lowercased().contains("inhalt") || question.lowercased().contains("steht in")
            do {
                if summaryRequested {
                    guard let selected else { throw transferError("Bitte wähle zuerst eine Datei in Branch oder in der Trefferliste aus.") }
                    let text = try await Task.detached(priority:.userInitiated) { try FileSearch.excerpt(selected) }.value
                    try Task.checkCancellation()
                    let answer = try await LocalFileAI.summarize(text,name:selected.lastPathComponent,question:question)
                    try Task.checkCancellation()
                    append("Botti",answer + "\n\nQuelle: \(selected.path)\nGrundlage: Textauszug, maximal 8 PDF-Seiten bzw. 8.000 Zeichen. KI-Antworten können Fehler enthalten.")
                } else {
                    let contextual = question.lowercased().contains("davon") && !previous.isEmpty ? "Vorherige Suche: \(previous)\nNeue Einschränkung: \(question)" : question
                    let query = await LocalFileAI.query(contextual)
                    try Task.checkCancellation()
                    let result = await Task.detached(priority:.userInitiated) { FileSearch.search(query,root:folder,stop:stop) }.value
                    try Task.checkCancellation()
                    hits = result.hits; results.reloadData(); lastQuestion = contextual
                    let total = ByteCountFormatter.string(fromByteCount:result.totalBytes,countStyle:.file)
                    let type = query.kind == "folder" ? "Ordner" : "Dateien"
                    let kindName = ["any":"alle Dateien","pdf":"PDF","image":"Bilder","document":"Dokumente","spreadsheet":"Tabellen","audio":"Audio","video":"Videos","folder":"Ordner"][query.kind] ?? "Dateien"
                    let filters = "Name: \(query.terms.isEmpty ? "beliebig" : query.terms.joined(separator:", ")) · Typ: \(kindName) · Zeitraum: \(query.days == 0 ? "alle" : "\(query.days) Tag(e)") · ab \(ByteCountFormatter.string(fromByteCount:query.minimumBytes,countStyle:.file))"
                    let incomplete = result.partial || result.inaccessible > 0
                    var response = "\(incomplete ? "Bisher gefunden" : "Gefunden"): \(result.count) \(type)" + (query.kind == "folder" ? "." : " mit insgesamt \(total).")
                    response += "\n\(filters)\nSuchbereich: \(folder.path)"
                    if result.count > hits.count { response += "\nDie Liste zeigt die ersten \(hits.count) Treffer in der gewählten Sortierung." }
                    if result.partial { response += "\nDie Suche wurde nach dem Zeit-/Dateilimit begrenzt. Bitte wähle einen kleineren Suchbereich; die Zahlen sind unvollständig." }
                    if result.inaccessible > 0 { response += "\n\(result.inaccessible) Bereiche/Dateien waren nicht lesbar; die Zahlen können unvollständig sein." }
                    response += "\nVersteckte Dateien, Verknüpfungsziele und Inhalte von App-Paketen werden nicht durchsucht."
                    if !query.usedAI { response += "\nLokale Stichwortsuche verwendet; die KI war nicht verfügbar oder konnte die Frage nicht auswerten." }
                    append("Botti",response)
                }
                RobotState.shared.celebrationUntil = Date(timeIntervalSinceNow:4)
            } catch is CancellationError { append("Botti","Suche gestoppt.") }
            catch { append("Botti",error.localizedDescription); RobotState.shared.concernUntil = Date(timeIntervalSinceNow:5) }
        }
    }
    @objc private func reveal() {
        guard hits.indices.contains(results.selectedRow), let app else { return }
        let url = hits[results.selectedRow].url, pane = app.activePane
        pane.navigate(isFolder(url) ? url : url.deletingLastPathComponent())
        if let row = pane.visibleFiles.firstIndex(where: { $0.path == url.path }) { pane.table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false); pane.table.scrollRowToVisible(row) }
        app.window.makeKeyAndOrderFront(nil)
    }
    @objc private func preview() { if let selectedURL { FilePreview.shared.show(selectedURL,sourceTable:results) } }
    func tableViewSelectionDidChange(_ notification: Notification) { FilePreview.shared.update(hits.indices.contains(results.selectedRow) ? hits[results.selectedRow].url : nil,sourceTable:results) }
    func numberOfRows(in tableView: NSTableView) -> Int { hits.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hit = hits[row]; let label = NSTextField(labelWithString:""); label.font = .systemFont(ofSize:11); label.textColor = BranchStyle.text; label.lineBreakMode = .byTruncatingMiddle
        switch tableColumn?.identifier.rawValue {
        case "size": label.stringValue = isFolder(hit.url) ? "—" : ByteCountFormatter.string(fromByteCount:hit.bytes,countStyle:.file)
        case "date": label.stringValue = hit.date.map { DateFormatter.localizedString(from:$0,dateStyle:.short,timeStyle:.none) } ?? "—"
        default: label.stringValue = hit.url.lastPathComponent; label.toolTip = hit.url.path
        }
        return label
    }
}
