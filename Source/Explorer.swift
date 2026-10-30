import AppKit

final class ExplorerClipboard {
    static let shared = ExplorerClipboard()
    private var cutChangeCount: Int?
    func write(_ urls: [URL], cut: Bool, pasteboard: NSPasteboard = .general) {
        guard !urls.isEmpty else { return }
        pasteboard.clearContents(); pasteboard.writeObjects(urls as [NSURL])
        cutChangeCount = cut ? pasteboard.changeCount : nil
    }
    func isCut(_ pasteboard: NSPasteboard = .general) -> Bool { cutChangeCount == pasteboard.changeCount }
    func consumeCut() { cutChangeCount = nil }
}
extension BrowserPane {
    func explorerCommands() -> NSStackView {
        let create = NSPopUpButton(frame:.zero,pullsDown:true); create.addItem(withTitle:"Neu")
        for (title,action) in [("Ordner",#selector(newFolder)),("Textdokument",#selector(newTextDocument))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; create.menu?.addItem(item)
        }
        let cut = button("scissors","Ausschneiden (Strg+X / ⌘X)",#selector(cutSelected))
        let copy = button("doc.on.doc","Kopieren (Strg+C / ⌘C)",#selector(copySelected))
        let paste = button("doc.on.clipboard","Einfügen (Strg+V / ⌘V)",#selector(pasteCopy))
        let rename = button("pencil","Umbenennen (F2)",#selector(renameSelected))
        let share = button("square.and.arrow.up","Teilen",#selector(shareSelected))
        let trash = button("trash","In den Papierkorb (Entf)",#selector(trashSelected))
        let sort = NSPopUpButton(frame:.zero,pullsDown:true); sort.addItem(withTitle:"Sortieren")
        for (i,name) in ["Name","Änderungsdatum","Typ","Größe"].enumerated() {
            let item = NSMenuItem(title:name,action:#selector(chooseSort(_:)),keyEquivalent:""); item.tag = i; item.target = self; sort.menu?.addItem(item)
        }
        sort.menu?.addItem(.separator())
        for (i,name) in ["Aufsteigend","Absteigend"].enumerated() {
            let item = NSMenuItem(title:name,action:#selector(chooseSort(_:)),keyEquivalent:""); item.tag = i+10; item.target = self; sort.menu?.addItem(item)
        }
        sort.menu?.delegate = self
        let mode = NSPopUpButton(frame:.zero,pullsDown:true); mode.addItem(withTitle:"Ansicht")
        for (i,name) in ["Details","Liste","Kompakte Details"].enumerated() {
            let item = NSMenuItem(title:name,action:#selector(chooseView(_:)),keyEquivalent:""); item.tag = i; item.target = self; mode.menu?.addItem(item)
        }
        mode.menu?.delegate = self
        let more = NSPopUpButton(frame:.zero,pullsDown:true); more.addItem(withTitle:"…"); more.toolTip = "Weitere Optionen"
        for (title,action) in [("Alles auswählen",#selector(selectAllFiles)),("Auswahl umkehren",#selector(invertSelection)),("Pfad kopieren",#selector(copyPath)),("Aktualisieren",#selector(refreshAll)),("Eigenschaften",#selector(showProperties))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; more.menu?.addItem(item)
        }
        let row = NSStackView(views:[create,cut,copy,paste,rename,share,trash,sort,mode,more,NSView(),favorite]); row.spacing = 4
        return row
    }
    @objc func selectAllFiles() { table.selectAll(nil) }
    @objc func invertSelection() { table.selectRowIndexes(IndexSet(visibleFiles.indices.filter { !table.selectedRowIndexes.contains($0) }),byExtendingSelection:false) }
    @objc func copyPath() {
        guard !selected.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selected.map(\.path).joined(separator:"\n"),forType:.string)
    }
    @objc func newTextDocument() {
        guard !busy, let name = input("Neues Textdokument",value:"Neues Textdokument.txt"), validName(name) else { return }
        do { try Data().write(to:current.appendingPathComponent(name),options:.withoutOverwriting); NotificationCenter.default.post(name:changed,object:nil) }
        catch { failure(error.localizedDescription) }
    }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(renameSelected): return !busy && selected.count == 1
        case #selector(cutSelected),#selector(trashSelected): return !busy && !selected.isEmpty
        case #selector(copySelected),#selector(shareSelected),#selector(showProperties),#selector(copyPath): return !selected.isEmpty
        case #selector(pasteCopy),#selector(pasteMove): return !busy && !readURLs(.general).isEmpty
        case #selector(newFolder),#selector(newTextDocument): return !busy
        default: return true
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(chooseSort(_:)) {
                let descriptor = table.sortDescriptors.first
                let active = item.tag >= 10 ? (descriptor?.ascending ?? true) == (item.tag == 10) : ["name","date","type","size"][item.tag] == (descriptor?.key ?? "name")
                item.state = active ? .on : .off
            } else if item.action == #selector(chooseView(_:)) { item.state = settings.integer(forKey:identifierKey + ".view") == item.tag ? .on : .off }
        }
    }
    @objc func showProperties() {
        guard let url = selected.first else { return }
        let values = try? url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.creationDateKey])
        let alert = NSAlert(); alert.messageText = url.lastPathComponent
        let size = isFolder(url) ? "Ordner" : ByteCountFormatter.string(fromByteCount:Int64(values?.fileSize ?? 0),countStyle:.file)
        let modified = values?.contentModificationDate.map { DateFormatter.localizedString(from:$0,dateStyle:.medium,timeStyle:.short) } ?? "—"
        alert.informativeText = "Pfad: \(url.path)\n\nGröße/Typ: \(size)\nGeändert: \(modified)"
        alert.addButton(withTitle:"Schließen"); alert.runModal()
    }
    @objc func shareSelected() {
        guard !selected.isEmpty else { return }
        NSSharingServicePicker(items:selected).show(relativeTo:table.visibleRect,of:table,preferredEdge:.maxY)
    }
    @objc func cutSelected() {
        guard !busy else { return }
        ExplorerClipboard.shared.write(selected,cut:true)
        if !selected.isEmpty { status.stringValue = "\(selected.count) zum Verschieben markiert · Am Ziel einfügen" }
    }
    @objc func focusAddress() { address.isHidden = true; path.isHidden = false; view.window?.makeFirstResponder(path); path.selectText(nil) }
    @objc func focusSearch() { view.window?.makeFirstResponder(search); search.selectText(nil) }
    @objc func breadcrumbClicked() { if let url = address.clickedPathItem?.url { navigate(url) } }
    @objc func goForward() { if let next = forwardHistory.popLast() { history.append(current); navigate(next,remember:false) } }
    @objc func chooseSort(_ sender: NSMenuItem) {
        let keys = ["name","date","type","size"]
        if sender.tag >= 10 {
            table.sortDescriptors = [NSSortDescriptor(key:table.sortDescriptors.first?.key ?? "name",ascending:sender.tag == 10)]; return
        }
        guard keys.indices.contains(sender.tag) else { return }
        let key = keys[sender.tag]
        let ascending = table.sortDescriptors.first?.key == key ? !(table.sortDescriptors.first?.ascending ?? true) : key != "date"
        table.sortDescriptors = [NSSortDescriptor(key:key,ascending:ascending)]
    }
    @objc func chooseView(_ sender: NSMenuItem) {
        table.tableColumns.forEach { $0.isHidden = sender.tag == 1 && $0.identifier.rawValue != "name" }
        table.headerView = sender.tag == 1 ? nil : detailsHeader
        table.rowHeight = sender.tag == 2 ? 23 : 30
        settings.set(sender.tag,forKey:identifierKey + ".view")
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { filter() }
    func sortExplorerFiles(_ values: [URL]) -> [URL] {
        let descriptor = table.sortDescriptors.first, key = descriptor?.key ?? "name", ascending = descriptor?.ascending ?? true
        // Read metadata once per item, not for every comparison.
        let metadata = Dictionary(uniqueKeysWithValues: values.map { ($0,(try? $0.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]))) })
        return values.sorted { a,b in
            let aFolder = isFolder(a), bFolder = isFolder(b)
            if aFolder != bFolder { return aFolder }
            var order: ComparisonResult
            switch key {
            case "size": let x = metadata[a]??.fileSize ?? 0, y = metadata[b]??.fileSize ?? 0; order = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            case "date": order = (metadata[a]??.contentModificationDate ?? .distantPast).compare(metadata[b]??.contentModificationDate ?? .distantPast)
            case "type": order = a.pathExtension.localizedStandardCompare(b.pathExtension)
            default: order = label(a).localizedStandardCompare(label(b))
            }
            if order == .orderedSame { order = label(a).localizedStandardCompare(label(b)) }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
    @objc func recursiveSearch() {
        let term = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !term.isEmpty else { filter(); return }
        searchToken?.request(); let token = StopRequest(); searchToken = token
        let root = current
        status.stringValue = "Suche in diesem Ordner und Unterordnern …"
        DispatchQueue.global(qos:.userInitiated).async {
            let result = FileSearch.search(FileQuery(terms:[term]),root:root,stop:token)
            DispatchQueue.main.async {
                guard !token.isRequested, self.current == root, self.search.stringValue == term else { return }
                self.recursiveResults = result.hits.map(\.url); self.visibleFiles = self.sortExplorerFiles(self.recursiveResults!); self.table.reloadData()
                self.status.stringValue = "\(result.count) Treffer in Unterordnern" + (result.partial || result.inaccessible > 0 || result.count > result.hits.count ? " · begrenztes Ergebnis, Suchbereich eingrenzen" : "")
            }
        }
    }
}

extension AppDelegate {
    func installExplorerMenus(_ menu: NSMenu, viewMenu: NSMenu) {
        let fileItem = NSMenuItem(); let fileMenu = NSMenu(title:"Datei"); fileItem.submenu = fileMenu; menu.insertItem(fileItem,at:1)
        for (title,tag) in [("Neuer Ordner …",0),("Neues Textdokument …",1),("Öffnen",2),("Umbenennen …",3),("Teilen …",4),("Eigenschaften …",5),("In den Papierkorb …",6)] {
            let item = NSMenuItem(title:title,action:#selector(explorerFileAction(_:)),keyEquivalent:""); item.tag = tag; item.target = self; fileMenu.addItem(item)
        }
        viewMenu.insertItem(.separator(),at:0)
        for (tag,title) in ["Details","Liste","Kompakte Details"].enumerated().reversed() {
            let item = NSMenuItem(title:title,action:#selector(explorerViewAction(_:)),keyEquivalent:""); item.tag = tag; item.target = self; viewMenu.insertItem(item,at:0)
        }
    }
    @objc func explorerViewAction(_ sender: NSMenuItem) { activePane.chooseView(sender) }
    @objc func explorerFileAction(_ sender: NSMenuItem) {
        let pane = activePane
        switch sender.tag {
        case 0: pane.newFolder()
        case 1: pane.newTextDocument()
        case 2: pane.openSelected()
        case 3: pane.renameSelected()
        case 4: pane.shareSelected()
        case 5: pane.showProperties()
        case 6: pane.trashSelected()
        default: break
        }
    }
}
