import AppKit

let testingUI = CommandLine.arguments.contains("--ui-test")
let settings = testingUI ? UserDefaults(suiteName: "de.branch.isolated-ui-test")! : UserDefaults.standard
if testingUI { settings.removePersistentDomain(forName: "de.branch.isolated-ui-test") }

enum BranchStyle {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name:nil) { appearance in appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark : light }
    }
    static let base = adaptive(rgb(255,255,255),rgb(25,25,25))
    static let sidebar = adaptive(rgb(243,243,243),rgb(32,32,32))
    static let raised = adaptive(rgb(255,255,255),rgb(25,25,25))
    static let mint = adaptive(rgb(0,103,192),rgb(102,183,255))
    static let gold = adaptive(rgb(221,163,32),rgb(245,196,83))
    static let text = NSColor.labelColor
    static let muted = NSColor.secondaryLabelColor
    static let selected = adaptive(rgb(229,241,251),rgb(51,63,76))
    static func symbol(_ name: String, color: NSColor) -> NSImage? {
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let image = source.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[color])) ?? source
        image.size = NSSize(width:20,height:20)
        return image
    }
    static func folderIcon() -> NSImage? { symbol("folder.fill", color: gold) }
}
final class BranchBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        BranchStyle.sidebar.setFill(); bounds.fill()
    }
}
final class BranchRow: NSTableRowView {
    var sidebar = false
    var alternate = false
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawBackground(in dirtyRect: NSRect) {
        (sidebar ? BranchStyle.sidebar : (alternate ? BranchStyle.raised : BranchStyle.base)).setFill()
        bounds.fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        BranchStyle.selected.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 6, yRadius: 6).fill()
        if sidebar {
            BranchStyle.mint.setFill()
            NSBezierPath(roundedRect:NSRect(x:3,y:6,width:3,height:max(0,bounds.height-12)),xRadius:1.5,yRadius:1.5).fill()
        }
    }
}
let fm = FileManager.default
let changed = Notification.Name("BaumFilesChanged")
let favoritesChanged = Notification.Name("BaumFavoritesChanged")
func isFolder(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])).map { $0.isDirectory == true && $0.isPackage != true } ?? false }
func label(_ url: URL) -> String { fm.displayName(atPath: url.path) }
func failure(_ message: String) { let a = NSAlert(); a.messageText = "Das hat nicht geklappt"; a.informativeText = message; a.runModal() }
func input(_ title: String, value: String = "") -> String? {
    let a = NSAlert(); a.messageText = title; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Abbrechen")
    let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 360, height: 25); a.accessoryView = field
    a.window.initialFirstResponder = field
    return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
}
func validName(_ name: String) -> Bool { !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":") }
final class TreeNode {
    let url: URL?
    let title: String
    var cached: [TreeNode]?
    init(_ url: URL?, title: String? = nil, children: [TreeNode]? = nil) { self.url = url; self.title = title ?? url.map(label) ?? ""; self.cached = children }
    func children() -> [TreeNode] {
        if let cached { return cached }
        guard let url else { return [] }
        let options: FileManager.DirectoryEnumerationOptions = settings.bool(forKey: "hidden") ? [] : [.skipsHiddenFiles]
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: options)) ?? []
        let nodes = items.filter(isFolder).sorted { label($0).localizedStandardCompare(label($1)) == .orderedAscending }.map { TreeNode($0) }
        cached = nodes; return nodes
    }
}
final class FileTable: NSTableView {
    weak var pane: BrowserPane?
    @objc func undo(_ sender: Any?) { TransferCenter.shared.undoLast() }
    @objc func newTab(_ sender: Any?) { pane?.newTab() }
    @objc func closeTab(_ sender: Any?) { if let pane { pane.closeTab(at: pane.activeTab) } }
    @objc func cut(_ sender: Any?) { pane?.cutSelected() }
    @objc func copy(_ sender: Any?) { pane?.copySelected() }
    @objc func paste(_ sender: Any?) { pane?.pasteFiles(move: false) }
    @objc func moveHere(_ sender: Any?) { pane?.pasteFiles(move: true) }
    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        let control = event.modifierFlags.contains(.control), alt = event.modifierFlags.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if control || cmd {
            switch key {
            case "z": TransferCenter.shared.undoLast(); return
            case "x": pane?.cutSelected(); return
            case "c": pane?.copySelected(); return
            case "v": pane?.pasteFiles(move:alt); return
            case "a": selectAll(nil); return
            case "l": pane?.focusAddress(); return
            case "f": pane?.focusSearch(); return
            case "t": pane?.newTab(); return
            case "w": if let pane { pane.closeTab(at:pane.activeTab) }; return
            case "n" where event.modifierFlags.contains(.shift): pane?.newFolder(); return
            default: break
            }
        }
        if alt {
            switch event.keyCode { case 123: pane?.goBack(); return; case 124: pane?.goForward(); return; case 126: pane?.goUp(); return; default: break }
        }
        if event.keyCode == 120 { pane?.renameSelected(); return }
        if event.keyCode == 96 { pane?.refreshAll(); return }
        if event.keyCode == 117 { pane?.trashSelected(); return }
        if event.keyCode == 51 && !cmd && !control { pane?.goBack(); return }
        if event.keyCode == 53 && FilePreview.shared.isVisible { FilePreview.shared.close(); return }
        if event.keyCode == 49 && !cmd { pane?.previewSelected(); return }
        if event.keyCode == 36 { pane?.openSelected(); return }
        if cmd && event.keyCode == 51 { pane?.trashSelected(); return }
        if cmd && event.charactersIgnoringModifiers == "c" { pane?.copySelected(); return }
        if cmd && event.charactersIgnoringModifiers == "v" { pane?.pasteFiles(move: event.modifierFlags.contains(.option)); return }
        super.keyDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let translated = NSEvent.mouseEvent(with:event.type,location:event.locationInWindow,modifierFlags:event.modifierFlags.subtracting(.control).union(.command),timestamp:event.timestamp,windowNumber:event.windowNumber,context:nil,eventNumber:event.eventNumber,clickCount:event.clickCount,pressure:event.pressure) {
            super.mouseDown(with:translated)
        } else { super.mouseDown(with:event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return super.menu(for: event)
    }
}
final class BrowserPane: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSUserInterfaceValidations {
    let identifierKey: String
    let outline = NSOutlineView()
    let table = FileTable()
    let path = NSTextField()
    let status = NSTextField(labelWithString: "")
    let search = NSSearchField()
    let favorite = NSButton()
    let innerSplit = NSSplitView()
    let tabButtons = NSStackView()
    var tabs: [BrowserTab] = []
    var activeTab = 0
    var roots: [TreeNode] = []
    var files: [URL] = []
    var visibleFiles: [URL] = []
    var current: URL
    var history: [URL] = []
    var forwardHistory: [URL] = []
    let address = NSPathControl()
    var detailsHeader: NSTableHeaderView?
    var searchToken: StopRequest?
    var recursiveResults: [URL]?
    var syncing = false
    var busy: Bool { TransferCenter.shared.busy }
    init(_ key: String) {
        identifierKey = key
        current = URL(fileURLWithPath: settings.string(forKey: key) ?? fm.homeDirectoryForCurrentUser.path)
        if let data = settings.data(forKey: key + ".tabs"), let saved = try? JSONDecoder().decode(PaneSession.self, from: data) {
            let session = saved.sanitized(); tabs = session.tabs; activeTab = session.selected
            current = URL(fileURLWithPath: tabs[activeTab].path); history = tabs[activeTab].history.map { URL(fileURLWithPath: $0) }
        } else { tabs = [BrowserTab(path: current.path)] }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: BranchStyle.symbol(symbol, color: BranchStyle.text)!, target: self, action: action)
        b.bezelStyle = .texturedRounded; b.contentTintColor = BranchStyle.text; b.toolTip = tip; return b
    }
    override func loadView() {
        view = BranchBackground(); view.translatesAutoresizingMaskIntoConstraints = false
        let tabsScroll = NSScrollView(); tabsScroll.documentView = tabButtons; tabsScroll.hasHorizontalScroller = true; tabsScroll.autohidesScrollers = true; tabsScroll.drawsBackground = false
        tabButtons.orientation = .horizontal; tabButtons.spacing = 8
        let addTab = button("plus", "Neuer Tab (⌘T)", #selector(newTab))
        let tabRow = NSStackView(views: [tabsScroll, addTab]); tabRow.spacing = 8
        tabsScroll.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let back = button("arrow.left", "Zurück (Alt+Links)", #selector(goBack))
        let forward = button("arrow.right", "Vorwärts (Alt+Rechts)", #selector(goForward))
        let up = button("arrow.up", "Übergeordneter Ordner", #selector(goUp))
        let refresh = button("arrow.clockwise", "Aktualisieren", #selector(refreshAll))
        favorite.image = BranchStyle.symbol("star", color: BranchStyle.gold)
        favorite.contentTintColor = BranchStyle.gold
        favorite.target = self; favorite.action = #selector(toggleFavorite); favorite.bezelStyle = .texturedRounded; favorite.toolTip = "Aktuellen Ordner als Favorit hinzufügen oder entfernen"
        path.font = .systemFont(ofSize: 12); path.target = self; path.action = #selector(goPath); path.placeholderString = "Ordnerpfad eingeben …"
        path.textColor = BranchStyle.text; path.backgroundColor = BranchStyle.base; path.focusRingType = .none
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        address.pathStyle = .standard; address.target = self; address.action = #selector(breadcrumbClicked)
        address.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        path.isHidden = true
        let addressBox = NSStackView(views:[address,path])
        let nav = NSStackView(views: [back, forward, up, refresh, addressBox, search]); nav.spacing = 6
        search.placeholderString = "Ordner durchsuchen"; search.delegate = self; search.textColor = BranchStyle.text; search.focusRingType = .none
        search.target = self; search.action = #selector(recursiveSearch); search.sendsSearchStringImmediately = false; search.sendsWholeSearchString = true
        search.widthAnchor.constraint(equalToConstant:155).isActive = true
        search.toolTip = "Tippen: aktuellen Ordner filtern. Enter: auch Unterordner nach Namen durchsuchen."
        let actions = explorerCommands()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree")); col.title = "Verzeichnisbaum"; outline.addTableColumn(col); outline.outlineTableColumn = col
        outline.headerView = nil; outline.rowHeight = 30; outline.indentationPerLevel = 14; outline.style = .plain; outline.backgroundColor = BranchStyle.sidebar; outline.focusRingType = .none
        outline.dataSource = self; outline.delegate = self; outline.autoresizesOutlineColumn = true
        outline.registerForDraggedTypes([.fileURL]); outline.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        let treeScroll = NSScrollView(); treeScroll.documentView = outline; treeScroll.hasVerticalScroller = true; treeScroll.hasHorizontalScroller = true; treeScroll.autohidesScrollers = true; treeScroll.backgroundColor = BranchStyle.sidebar
        for (id, title, width) in [("name", "Name", 270.0), ("date", "Änderungsdatum", 145.0), ("type", "Typ", 100.0), ("size", "Größe", 85.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; c.minWidth = id == "name" ? 130 : 65
            c.sortDescriptorPrototype = NSSortDescriptor(key:id,ascending:true)
            table.addTableColumn(c)
        }
        detailsHeader = table.headerView
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle; table.rowHeight = 32; table.usesAlternatingRowBackgroundColors = false; table.backgroundColor = BranchStyle.base; table.focusRingType = .none
        table.allowsMultipleSelection = true; table.dataSource = self; table.delegate = self; table.pane = self
        table.target = self; table.doubleAction = #selector(openSelected)
        table.registerForDraggedTypes([.fileURL]); table.setDraggingSourceOperationMask([.copy, .move], forLocal: true); table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let menu = NSMenu()
        for (title, action) in [("Öffnen", #selector(openSelected)), ("Vorschau (Leertaste)", #selector(previewSelected)), ("An Schnellzugriff anheften", #selector(favoriteSelected)), ("Umbenennen …", #selector(renameSelected)), ("Ausschneiden", #selector(cutSelected)), ("Kopieren", #selector(copySelected)), ("Hier einfügen", #selector(pasteCopy)), ("Hierher verschieben", #selector(pasteMove)), ("Teilen …", #selector(shareSelected)), ("Eigenschaften …", #selector(showProperties)), ("In den Papierkorb …", #selector(trashSelected))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        table.menu = menu
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true; scroll.backgroundColor = BranchStyle.base
        innerSplit.isVertical = true; innerSplit.dividerStyle = .thin; innerSplit.addArrangedSubview(treeScroll); innerSplit.addArrangedSubview(scroll)
        innerSplit.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        status.font = .systemFont(ofSize: 11); status.textColor = BranchStyle.muted
        for v in [tabRow, nav, actions, innerSplit, status] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 8), tabRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10), tabRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            nav.topAnchor.constraint(equalTo: tabRow.bottomAnchor, constant: 6), nav.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10), nav.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            actions.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 10), actions.leadingAnchor.constraint(equalTo: nav.leadingAnchor), actions.trailingAnchor.constraint(equalTo: nav.trailingAnchor),
            innerSplit.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 12), innerSplit.leadingAnchor.constraint(equalTo: view.leadingAnchor), innerSplit.trailingAnchor.constraint(equalTo: view.trailingAnchor), innerSplit.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -7),
            status.leadingAnchor.constraint(equalTo: nav.leadingAnchor), status.trailingAnchor.constraint(equalTo: nav.trailingAnchor), status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            treeScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 135), scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 190), search.widthAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildTree), name: favoritesChanged, object: nil)
        rebuildTree(); navigate(isFolder(current) ? current : fm.homeDirectoryForCurrentUser, remember: false); renderTabs(); let mode = NSMenuItem(); mode.tag = settings.integer(forKey:identifierKey + ".view"); chooseView(mode)
    }
    override func viewDidAppear() { super.viewDidAppear(); innerSplit.setPosition(190, ofDividerAt: 0) }
    var favorites: [String] {
        get { settings.stringArray(forKey: "favorites") ?? ["Desktop","Downloads","Documents","Pictures","Music","Movies"].map { fm.homeDirectoryForCurrentUser.appendingPathComponent($0).path } }
        set { settings.set(newValue, forKey: "favorites"); NotificationCenter.default.post(name: favoritesChanged, object: nil) }
    }
    @objc func rebuildTree() {
        let expanded = (0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? TreeNode }.filter { outline.isItemExpanded($0) }.compactMap { $0.url?.path }
        roots = [TreeNode(nil, title: "SCHNELLZUGRIFF", children: favorites.map { TreeNode(URL(fileURLWithPath: $0)) }), TreeNode(nil, title: "DIESER MAC", children: [TreeNode(fm.homeDirectoryForCurrentUser, title: "Benutzerordner"), TreeNode(URL(fileURLWithPath: "/"), title: "Macintosh HD"), TreeNode(URL(fileURLWithPath: "/Volumes"), title: "Laufwerke")])]
        syncing = true; outline.reloadData()
        for root in roots { outline.expandItem(root) }
        if expanded.isEmpty, let home = roots.last?.children().first { outline.expandItem(home) }
        var row = 0
        while row < outline.numberOfRows {
            if let node = outline.item(atRow: row) as? TreeNode, let p = node.url?.path, expanded.contains(p) { outline.expandItem(node) }
            row += 1
        }
        syncing = false; updateStar(); syncTree()
    }
    func updateStar() { favorite.image = BranchStyle.symbol(favorites.contains(current.path) ? "star.fill" : "star", color: BranchStyle.gold) }
    func navigate(_ url: URL, remember: Bool = true) {
        guard isFolder(url) else { failure("Dieser Ordner ist nicht erreichbar: \(url.path)"); return }
        do {
            let options: FileManager.DirectoryEnumerationOptions = settings.bool(forKey: "hidden") ? [] : [.skipsHiddenFiles]
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey], options: options)
            if remember && current != url { history.append(current); forwardHistory.removeAll() }
            searchToken?.request(); recursiveResults = nil
            current = url.standardizedFileURL; files = contents.sorted { a, b in
                if isFolder(a) != isFolder(b) { return isFolder(a) }; return label(a).localizedStandardCompare(label(b)) == .orderedAscending
            }
            settings.set(current.path, forKey: identifierKey); path.stringValue = current.path; address.url = current; path.isHidden = true; address.isHidden = false; search.placeholderString = "\(label(current)) durchsuchen"
            search.stringValue = ""; filter(); updateStar(); syncTree(); persistTabs(); renderTabs()
        } catch { failure("\(url.path)\n\n\(error.localizedDescription)") }
    }
    func syncTree() {
        syncing = true; defer { syncing = false }
        func reveal(_ node: TreeNode) -> TreeNode? {
            guard let u = node.url else { return nil }
            if u.standardizedFileURL == current { return node }
            let prefix = u.path == "/" ? "/" : u.path + "/"
            guard current.path.hasPrefix(prefix) else { return nil }
            outline.expandItem(node)
            for child in node.children() { if let found = reveal(child) { return found } }
            return nil
        }
        for root in roots {
            for node in root.children() {
                if let found = reveal(node) { let r = outline.row(forItem: found); if r >= 0 { outline.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false); outline.scrollRowToVisible(r) }; return }
            }
        }
    }
    func filter() {
        let query = search.stringValue
        searchToken?.request()
        let selection = Set(selected)
        visibleFiles = sortExplorerFiles(recursiveResults ?? (query.isEmpty ? files : files.filter { label($0).localizedCaseInsensitiveContains(query) }))
        table.reloadData(); table.selectRowIndexes(IndexSet(visibleFiles.indices.filter { selection.contains(visibleFiles[$0]) }),byExtendingSelection:false); status.stringValue = "\(visibleFiles.count) Elemente"
    }
    func controlTextDidChange(_ obj: Notification) { recursiveResults = nil; filter() }
    @objc func goBack() { if let last = history.popLast() { forwardHistory.append(current); navigate(last, remember: false) } }
    @objc func goUp() { navigate(current.deletingLastPathComponent()) }
    @objc func goPath() { navigate(URL(fileURLWithPath: (path.stringValue as NSString).expandingTildeInPath)); view.window?.makeFirstResponder(table) }
    @objc func chooseFolder() { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.directoryURL = current; if p.runModal() == .OK, let url = p.url { navigate(url) } }
    @objc func refreshAll() { guard !busy else { return }; let query = search.stringValue; rebuildTree(); navigate(current, remember: false); search.stringValue = query; filter() }
    @objc func toggleFavorite() { var f = favorites; if f.contains(current.path) { f.removeAll { $0 == current.path } } else { f.append(current.path) }; favorites = f }
    var selected: [URL] { table.selectedRowIndexes.compactMap { $0 < visibleFiles.count ? visibleFiles[$0] : nil } }
    @objc func favoriteSelected() { var f = favorites; for u in selected where isFolder(u) && !f.contains(u.path) { f.append(u.path) }; favorites = f }
    @objc func openSelected() { for u in selected { if isFolder(u) { navigate(u); break } else { NSWorkspace.shared.open(u) } } }
    @objc func previewSelected() { FilePreview.shared.toggle(selected.first,sourceTable:table) }
    func tableViewSelectionDidChange(_ notification: Notification) { FilePreview.shared.update(selected.first,sourceTable:table) }
    @objc func newFolder() {
        guard !busy else { return }
        guard let name = input("Neuer Ordner", value: "Neuer Ordner") else { return }
        guard validName(name) else { failure("Bitte gib einen gültigen Namen ohne / oder : ein."); return }
        do { try fm.createDirectory(at: current.appendingPathComponent(name), withIntermediateDirectories: false); NotificationCenter.default.post(name: changed, object: nil) } catch { failure(error.localizedDescription) }
    }
    @objc func renameSelected() {
        guard !busy else { return }
        guard selected.count == 1, let u = selected.first, let name = input("Umbenennen", value: u.lastPathComponent) else { return }
        guard validName(name) else { failure("Bitte gib einen gültigen Namen ohne / oder : ein."); return }
        if name == u.lastPathComponent { return }
        do { try fm.moveItem(at: u, to: u.deletingLastPathComponent().appendingPathComponent(name)); NotificationCenter.default.post(name: changed, object: nil) } catch { failure(error.localizedDescription) }
    }
    @objc func trashSelected() {
        guard !busy else { return }
        let urls = selected; guard !urls.isEmpty else { return }
        let a = NSAlert(); a.messageText = "\(urls.count) Objekte in den Papierkorb legen?"; a.informativeText = "Du kannst sie im Papierkorb wiederherstellen."; a.addButton(withTitle: "In den Papierkorb"); a.addButton(withTitle: "Abbrechen")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { for u in urls { try fm.trashItem(at: u, resultingItemURL: nil) } } catch { failure(error.localizedDescription) }
        NotificationCenter.default.post(name: changed, object: nil)
    }
    @objc func copySelected() { ExplorerClipboard.shared.write(selected,cut:false) }
    @objc func pasteCopy() { pasteFiles(move: false) }
    @objc func pasteMove() { pasteFiles(move: true) }
    func pasteFiles(move: Bool) {
        guard !busy else { return }
        let cut = ExplorerClipboard.shared.isCut()
        let urls = readURLs(NSPasteboard.general)
        guard !urls.isEmpty else { return }
        transfer(urls,to:current,copy:!(move || cut))
        if cut { ExplorerClipboard.shared.consumeCut() }
    }
    func readURLs(_ p: NSPasteboard) -> [URL] { (p.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? [] }
    func transfer(_ urls: [URL], to target: URL, copy: Bool) { TransferCenter.shared.start(urls, to: target, copy: copy) }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? TreeNode)?.children().count ?? roots.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? TreeNode)?.children()[index] ?? roots[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { let n = item as! TreeNode; return n.url != nil || !n.children().isEmpty }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { (item as! TreeNode).url == nil }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as! TreeNode).url != nil }
    func cell(_ title: String, image: NSImage? = nil, secondary: Bool = false, tint: NSColor? = nil) -> NSView {
        let c = NSTableCellView(); let t = NSTextField(labelWithString: title); t.lineBreakMode = .byTruncatingMiddle; t.font = .systemFont(ofSize: 12); t.textColor = secondary ? BranchStyle.muted : BranchStyle.text; t.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(t); c.textField = t
        var inset: CGFloat = 5
        if let image { let i = NSImageView(image: image); i.contentTintColor = tint; i.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(i); c.imageView = i; NSLayoutConstraint.activate([i.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4), i.centerYAnchor.constraint(equalTo: c.centerYAnchor), i.widthAnchor.constraint(equalToConstant: 18), i.heightAnchor.constraint(equalToConstant: 18)]); inset = 29 }
        NSLayoutConstraint.activate([t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: inset), t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4), t.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
        return c
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { let row = BranchRow(); row.sidebar = true; return row }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { let view = BranchRow(); view.alternate = row % 2 == 1; return view }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let n = item as! TreeNode
        if let url = n.url {
            let starred = favorites.contains(url.path)
            let symbol = url.path == "/" || url.path == "/Volumes" ? "externaldrive.fill" : (url == fm.homeDirectoryForCurrentUser ? "house.fill" : "folder.fill")
            return cell(n.title, image: BranchStyle.symbol(symbol, color: symbol == "folder.fill" || starred ? BranchStyle.gold : BranchStyle.muted))
        }
        let c = cell(n.title, secondary: true) as! NSTableCellView
        c.textField?.font = .systemFont(ofSize: 10, weight: .semibold)
        c.textField?.textColor = BranchStyle.muted
        return c
    }
    func outlineViewSelectionDidChange(_ notification: Notification) { guard !syncing, let node = outline.item(atRow: outline.selectedRow) as? TreeNode, let url = node.url else { return }; navigate(url) }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleFiles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let u = visibleFiles[row]; let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        switch tableColumn?.identifier.rawValue {
        case "type": return cell(isFolder(u) ? "Dateiordner" : (u.pathExtension.isEmpty ? "Datei" : u.pathExtension.uppercased() + "-Datei"),secondary:true)
        case "size": return cell(isFolder(u) ? "—" : ByteCountFormatter.string(fromByteCount: Int64(v?.fileSize ?? 0), countStyle: .file), secondary: true)
        case "date": return cell(v?.contentModificationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—", secondary: true)
        default: return cell(label(u), image: isFolder(u) ? BranchStyle.folderIcon() : NSWorkspace.shared.icon(forFile: u.path), tint: isFolder(u) ? BranchStyle.gold : nil)
        }
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { visibleFiles[row] as NSURL }
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? { (item as? TreeNode)?.url as NSURL? }
    func dragOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) && info.draggingSourceOperationMask.contains(.move) { return .move }
        return flags.contains(.control) || flags.contains(.option) || !info.draggingSourceOperationMask.contains(.move) ? .copy : .move
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard !busy, !readURLs(info.draggingPasteboard).isEmpty else { return [] }
        if row >= 0 && row < visibleFiles.count && isFolder(visibleFiles[row]) && dropOperation == .on { tableView.setDropRow(row, dropOperation: .on) } else { tableView.setDropRow(-1, dropOperation: .on) }
        return dragOperation(info)
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool { let target = row >= 0 && row < visibleFiles.count && isFolder(visibleFiles[row]) ? visibleFiles[row] : current; transfer(readURLs(info.draggingPasteboard), to: target, copy: dragOperation(info) == .copy); return true }
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation { guard !busy, let n = item as? TreeNode, n.url != nil, !readURLs(info.draggingPasteboard).isEmpty else { return [] }; outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex); return dragOperation(info) }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool { guard let url = (item as? TreeNode)?.url else { return false }; transfer(readURLs(info.draggingPasteboard), to: url, copy: dragOperation(info) == .copy); return true }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var robotHeight: NSLayoutConstraint?
    var pendingPlacement: Int?
    var window: NSWindow!
    let split = NSSplitViewController()
    let left = BrowserPane("leftPath")
    let right = BrowserPane("rightPath")
    var splitButton: NSButton!
    let robot = RobotView(frame: .zero)
    lazy var fileChat = FileChat(app: self)
    let workspaceButton = NSPopUpButton(frame: .zero, pullsDown: true)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = testingUI && CommandLine.arguments.contains("--light-check") ? NSAppearance(named:.aqua) : (testingUI && CommandLine.arguments.contains("--dark-check") ? NSAppearance(named:.darkAqua) : nil)
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Branch beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title: "Bearbeiten"); editItem.submenu = edit
        for (name, selector, key) in [("Ausschneiden", "cut:", "x"), ("Kopieren", "copy:", "c"), ("Einfügen", "paste:", "v"), ("Alles auswählen", "selectAll:", "a")] { edit.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key) }
        edit.addItem(withTitle: "Übertragung rückgängig", action: #selector(FileTable.undo(_:)), keyEquivalent: "z")
        let tabMenuItem = NSMenuItem(); menu.addItem(tabMenuItem); let tabMenu = NSMenu(title: "Tabs"); tabMenuItem.submenu = tabMenu
        let newTabItem = tabMenu.addItem(withTitle: "Neuer Tab", action: #selector(addActiveTab), keyEquivalent: "t"); newTabItem.target = self
        let closeTabItem = tabMenu.addItem(withTitle: "Tab schließen", action: #selector(closeActiveTab), keyEquivalent: "w"); closeTabItem.target = self
        let moveItem = edit.addItem(withTitle: "Hierher verschieben", action: #selector(FileTable.moveHere(_:)), keyEquivalent: "v"); moveItem.keyEquivalentModifierMask = [.command, .option]
        let viewItem = NSMenuItem(); menu.addItem(viewItem); let vmenu = NSMenu(title: "Ansicht"); viewItem.submenu = vmenu
        let toggle = vmenu.addItem(withTitle: "Zweite Ansicht umschalten", action: #selector(toggleSplit), keyEquivalent: "2"); toggle.target = self
        let chatItem = vmenu.addItem(withTitle: "Botti · Datei-Chat", action: #selector(openFileChat), keyEquivalent: "j"); chatItem.target = self
        let hidden = vmenu.addItem(withTitle: "Versteckte Dateien anzeigen", action: #selector(toggleHidden(_:)), keyEquivalent: "."); hidden.target = self; hidden.state = settings.bool(forKey: "hidden") ? .on : .off
        installExplorerMenus(menu,viewMenu:vmenu)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.delegate = self; window.backgroundColor = BranchStyle.base; window.titlebarAppearsTransparent = true
        window.title = "Branch"; window.minSize = NSSize(width: 720, height: 500); window.setFrameAutosaveName("BaumWindow")
        let root = NSViewController(); root.view = BranchBackground()
        let title = NSTextField(labelWithString: "Branch"); title.font = .systemFont(ofSize: 17, weight: .semibold); title.textColor = BranchStyle.mint
        let subtitle = NSTextField(labelWithString: "Datei-Explorer für deinen Mac"); subtitle.textColor = BranchStyle.muted; subtitle.font = .systemFont(ofSize: 12)
        let titles = NSStackView(views: [title, subtitle]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        splitButton = NSButton(title: "Zweite Ansicht", target: self, action: #selector(toggleSplit)); splitButton.bezelStyle = .rounded; splitButton.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil); splitButton.imagePosition = .imageLeading; splitButton.contentTintColor = BranchStyle.mint
        workspaceButton.bezelStyle = .rounded; rebuildWorkspaces()
        let navigation = NSStackView(views:[workspaceButton,splitButton]); navigation.spacing = 8
        let controls = NSStackView(views:[navigation,desktopActions()]); controls.spacing = 12
        let headerContent = NSStackView(views:[titles,NSView(),controls]); headerContent.spacing = 12
        let header: NSView
        header = headerContent
        // Two compact rows keep all actions reachable in a half-width window.
        controls.orientation = .vertical; controls.alignment = .trailing; controls.spacing = 6
        split.splitView.isVertical = true
        split.addSplitViewItem(NSSplitViewItem(viewController: left)); split.addSplitViewItem(NSSplitViewItem(viewController: right))
        for item in split.splitViewItems { item.minimumThickness = 380 }
        root.addChild(split)
        robot.onClick = { [weak self] in self?.fileChat.present() }
        let transferBar = TransferCenter.shared.bar
        for v in [header, split.view, transferBar, robot] { v.translatesAutoresizingMaskIntoConstraints = false; root.view.addSubview(v) }
        robotHeight = robot.heightAnchor.constraint(equalToConstant:92)
        NSLayoutConstraint.activate([header.topAnchor.constraint(equalTo: root.view.topAnchor, constant: 16), header.leadingAnchor.constraint(equalTo: root.view.leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: root.view.trailingAnchor, constant: -18), split.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14), split.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor), split.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor), split.view.bottomAnchor.constraint(equalTo: robot.topAnchor, constant: -6), transferBar.leadingAnchor.constraint(equalTo: root.view.leadingAnchor, constant: 14), transferBar.trailingAnchor.constraint(equalTo: robot.leadingAnchor, constant: -10), transferBar.centerYAnchor.constraint(equalTo: robot.centerYAnchor), robot.trailingAnchor.constraint(equalTo: root.view.trailingAnchor, constant: -10), robot.bottomAnchor.constraint(equalTo: root.view.bottomAnchor, constant: -6), robot.widthAnchor.constraint(equalToConstant: 310), robotHeight!])
        window.contentViewController = root
        if !testingUI && !settings.bool(forKey:"explorerInterfaceInstalled") { settings.set(false,forKey:"dual"); settings.set(true,forKey:"explorerInterfaceInstalled") }
        let dual = settings.object(forKey: "dual") == nil || settings.bool(forKey: "dual")
        split.splitViewItems[1].isCollapsed = !dual; updateSplitTitle()
        window.setContentSize(NSSize(width: 1360, height: 780))
        if !window.setFrameUsingName("BaumWindow") { window.center() }
        root.view.layoutSubtreeIfNeeded(); split.splitView.setPosition(split.view.bounds.width / 2, ofDividerAt: 0)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(left.table); NSApp.activate(ignoringOtherApps: true)
        if let idx = CommandLine.arguments.firstIndex(of: "--ui-test"), CommandLine.arguments.count > idx + 1 {
            let output = CommandLine.arguments[idx + 1]
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
                self.window.contentView?.layoutSubtreeIfNeeded()
                assert(self.left.table.numberOfRows > 0)
                assert(self.left.outline.numberOfRows > 7)
                do { try testUIFeatures(self) } catch { print("UI FEATURE TEST FAILED: \(error)"); exit(1) }
                let oldFavorites = self.left.favorites
                self.left.toggleFavorite(); assert(self.left.favorites.contains(self.left.current.path) != oldFavorites.contains(self.left.current.path))
                self.left.favorites = oldFavorites
                let initial = self.split.splitViewItems[1].isCollapsed
                self.toggleSplit(); assert(self.split.splitViewItems[1].isCollapsed != initial)
                self.toggleSplit(); assert(self.split.splitViewItems[1].isCollapsed == initial)
                self.window.contentView?.layoutSubtreeIfNeeded()
                if CommandLine.arguments.contains("--transfer-preview") {
                    TransferCenter.shared.status.isHidden = true; TransferCenter.shared.stopButton.isHidden = false
                    RobotState.shared.transferring = true; RobotState.shared.transferText = ""
                    RobotState.shared.snapshot = TransferSnapshot(done:12,total:30,bytes:480_000_000,totalBytes:1_200_000_000,rate:24_000_000,seconds:30)
                }
                if CommandLine.arguments.contains("--duck-preview") {
                    let state = RobotState.shared
                    state.transferring = false; state.searching = false; state.celebrationUntil = .distantPast; state.concernUntil = .distantPast
                    for (index,time) in [0.0,6.4,6.8,7.2,7.6].enumerated() {
                        self.robot.previewTime = time
                        if let bitmap = self.robot.bitmapImageRepForCachingDisplay(in:self.robot.bounds) {
                            self.robot.cacheDisplay(in:self.robot.bounds,to:bitmap)
                            try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:output + ".pose-\(index).png"))
                        }
                    }
                    self.robot.previewTime = 0
                }
                if CommandLine.arguments.contains("--layout-preview") {
                    let item = NSMenuItem(); item.tag = WindowPlacement.left.rawValue; self.placeWindow(item)
                    self.window.contentView?.layoutSubtreeIfNeeded()
                }
                if let view = self.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
                }
                print("TREE frame \(self.left.outline.frame), rows \(self.left.outline.numberOfRows), scroll \(String(describing: self.left.outline.enclosingScrollView?.frame))")
                print("PASS UI: directory listing, tree, split toggle. Left: \(self.left.view.frame), Right: \(self.right.view.frame)")
                if CommandLine.arguments.contains("--design-check") { print("DESIGN READY"); fflush(stdout); return }
                if let previewIndex = CommandLine.arguments.firstIndex(of: "--preview-check"), CommandLine.arguments.count > previewIndex + 1 {
                    FilePreview.shared.show(URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1])); print("PREVIEW READY"); fflush(stdout); return
                }
                if CommandLine.arguments.contains("--robot-check") {
                    self.fileChat.present(); print("ROBOT CHAT READY"); fflush(stdout); return
                }
                NSApp.terminate(nil)
            }
        }
    }
    @objc func openFileChat() { fileChat.present() }
    func updateSplitTitle() { let dual = !split.splitViewItems[1].isCollapsed; splitButton.title = dual ? "Eine Ansicht" : "Zweite Ansicht"; window.minSize = NSSize(width: dual ? 900 : 720, height: 390) }
    @objc func toggleSplit() { let item = split.splitViewItems[1]; if item.isCollapsed && window.frame.width < 1000 { var frame = window.frame; frame.size.width = min(1360, window.screen?.visibleFrame.width ?? 1360); window.setFrame(frame, display: true, animate: true) }; item.isCollapsed.toggle(); if !item.isCollapsed { split.view.layoutSubtreeIfNeeded(); split.splitView.setPosition(split.view.bounds.width / 2, ofDividerAt: 0) }; settings.set(!item.isCollapsed, forKey: "dual"); updateSplitTitle() }
    @objc func toggleHidden(_ sender: NSMenuItem) { let show = !settings.bool(forKey: "hidden"); settings.set(show, forKey: "hidden"); sender.state = show ? .on : .off; NotificationCenter.default.post(name: changed, object: nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if left.busy || right.busy { let a = NSAlert(); a.messageText = "Dateiübertragung läuft"; a.informativeText = "Bitte warte, bis das Kopieren oder Verschieben abgeschlossen ist."; a.runModal(); return .terminateCancel }; return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidBecomeActive(_ notification: Notification) { if window != nil { NotificationCenter.default.post(name: changed, object: nil) } }
}
if CommandLine.arguments.contains("--self-test") { do { try selfTest(); try testRobotSearchAndSpeed() } catch { print(error); exit(1) } } else if CommandLine.arguments.contains("--ai-test") {
    Task { do { try await testLocalAI(); exit(0) } catch { print(error); exit(1) } }; RunLoop.main.run()
} else {
    let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
}
