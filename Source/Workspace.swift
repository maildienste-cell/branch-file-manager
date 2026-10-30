import AppKit

struct BrowserTab: Codable {
    var path: String
    var history: [String] = []
}
struct PaneSession: Codable {
    var tabs: [BrowserTab]
    var selected: Int
    func sanitized() -> PaneSession {
        let valid = tabs.isEmpty ? [BrowserTab(path: fm.homeDirectoryForCurrentUser.path)] : tabs
        return PaneSession(tabs: valid, selected: min(max(0, selected), valid.count - 1))
    }
}
struct SavedWorkspace: Codable {
    let id: UUID
    var name: String
    var left: PaneSession
    var right: PaneSession
    var dual: Bool
}
final class WorkspaceStore {
    static let shared = WorkspaceStore()
    private let key = "savedWorkspaces.v1"
    var items: [SavedWorkspace] {
        get { guard let data = settings.data(forKey: key) else { return [] }; return (try? JSONDecoder().decode([SavedWorkspace].self, from: data)) ?? [] }
        set { if let data = try? JSONEncoder().encode(newValue) { settings.set(data, forKey: key) } }
    }
}
extension BrowserPane {
    func persistTabs() {
        tabs[activeTab].path = current.path; tabs[activeTab].history = history.map(\.path)
        let session = PaneSession(tabs: tabs, selected: activeTab)
        if let data = try? JSONEncoder().encode(session) { settings.set(data, forKey: identifierKey + ".tabs") }
    }
    var session: PaneSession { PaneSession(tabs: tabs, selected: activeTab) }
    func renderTabs() {
        for v in tabButtons.arrangedSubviews { tabButtons.removeArrangedSubview(v); v.removeFromSuperview() }
        for (index, tab) in tabs.enumerated() {
            let url = URL(fileURLWithPath: tab.path)
            let b = NSButton(title: label(url), target: self, action: #selector(selectTab(_:)))
            b.tag = index; b.bezelStyle = .rounded; b.setButtonType(.toggle); b.state = index == activeTab ? .on : .off
            b.contentTintColor = BranchStyle.text
            b.attributedTitle = NSAttributedString(string:label(url),attributes:[.foregroundColor:BranchStyle.text,.font:NSFont.systemFont(ofSize:12)])
            b.image = BranchStyle.symbol(index == activeTab ? "folder.fill" : "folder", color: index == activeTab ? BranchStyle.mint : BranchStyle.muted); b.imagePosition = .imageLeading
            b.toolTip = tab.path; b.widthAnchor.constraint(equalToConstant: 130).isActive = true
            (b.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
            let close = button("xmark", "Tab schließen", #selector(closeTab(_:))); close.tag = index; close.isEnabled = tabs.count > 1
            close.widthAnchor.constraint(equalToConstant: 24).isActive = true
            let group = NSStackView(views: [b, close]); group.spacing = 1
            tabButtons.addArrangedSubview(group)
        }
        tabButtons.frame = NSRect(x: 0, y: 0, width: CGFloat(tabs.count) * 163, height: 30)
        if !tabs.isEmpty { tabButtons.scrollToVisible(NSRect(x: CGFloat(activeTab)*163, y: 0, width: 160, height: 30)) }
    }
    @objc func newTab() {
        persistTabs(); tabs.append(BrowserTab(path: current.path)); activateTab(tabs.count - 1)
    }
    @objc func selectTab(_ sender: NSButton) { persistTabs(); activateTab(sender.tag) }
    func activateTab(_ index: Int) {
        forwardHistory.removeAll(); searchToken?.request()
        guard tabs.indices.contains(index) else { return }
        activeTab = index; history = tabs[index].history.map { URL(fileURLWithPath: $0) }
        let url = URL(fileURLWithPath: tabs[index].path)
        if isFolder(url) { navigate(url, remember: false) }
        else {
            navigate(fm.homeDirectoryForCurrentUser, remember: false)
            failure("Der gespeicherte Ordner ist nicht erreichbar: \(url.path)\nDer Benutzerordner wurde geöffnet.")
        }
        renderTabs(); view.window?.makeFirstResponder(table)
    }
    @objc func closeTab(_ sender: NSButton) { closeTab(at: sender.tag) }
    func closeTab(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        persistTabs(); tabs.remove(at: index)
        let next = index < activeTab ? activeTab - 1 : min(activeTab, tabs.count - 1)
        activateTab(next)
    }
    func restore(_ saved: PaneSession) {
        let normalized = saved.sanitized(); tabs = normalized.tabs; activateTab(normalized.selected)
    }
}
extension AppDelegate {
    var activePane: BrowserPane {
        if !split.splitViewItems[1].isCollapsed, let responder = window.firstResponder as? NSView, responder.isDescendant(of: right.view) { return right }
        return left
    }
    @objc func addActiveTab() { activePane.newTab() }
    @objc func closeActiveTab() { let pane = activePane; pane.closeTab(at: pane.activeTab) }
    func rebuildWorkspaces() {
        workspaceButton.removeAllItems(); workspaceButton.addItem(withTitle: "Arbeitsbereiche")
        let save = NSMenuItem(title: "Aktuellen Arbeitsbereich speichern …", action: #selector(saveWorkspace), keyEquivalent: ""); save.target = self; workspaceButton.menu?.addItem(save)
        let items = WorkspaceStore.shared.items
        if !items.isEmpty {
            workspaceButton.menu?.addItem(.separator())
            for saved in items {
                let item = NSMenuItem(title: saved.name, action: #selector(openWorkspace(_:)), keyEquivalent: ""); item.target = self; item.representedObject = saved.id.uuidString; workspaceButton.menu?.addItem(item)
            }
            workspaceButton.menu?.addItem(.separator())
            let remove = NSMenuItem(title: "Arbeitsbereich entfernen", action: nil, keyEquivalent: ""); let submenu = NSMenu()
            for saved in items { let item = NSMenuItem(title: saved.name, action: #selector(removeWorkspace(_:)), keyEquivalent: ""); item.target = self; item.representedObject = saved.id.uuidString; submenu.addItem(item) }
            remove.submenu = submenu; workspaceButton.menu?.addItem(remove)
        }
    }
    func snapshotWorkspace(name: String, id: UUID = UUID()) -> SavedWorkspace {
        left.persistTabs(); right.persistTabs()
        return SavedWorkspace(id: id, name: name, left: left.session, right: right.session, dual: !split.splitViewItems[1].isCollapsed)
    }
    @objc func saveWorkspace() {
        guard let value = input("Arbeitsbereich speichern", value: "Mein Arbeitsbereich") else { return }
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }
        var items = WorkspaceStore.shared.items
        if let index = items.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            let a = NSAlert(); a.messageText = "Arbeitsbereich „\(name)“ aktualisieren?"; a.informativeText = "Die gespeicherten Tabs und Ordner werden durch die aktuelle Ansicht ersetzt."; a.addButton(withTitle: "Aktualisieren"); a.addButton(withTitle: "Abbrechen")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            items[index] = snapshotWorkspace(name: name, id: items[index].id)
        } else { items.append(snapshotWorkspace(name: name)) }
        WorkspaceStore.shared.items = items; rebuildWorkspaces()
    }
    func restoreWorkspace(_ saved: SavedWorkspace) {
        left.restore(saved.left); right.restore(saved.right)
        if saved.dual == split.splitViewItems[1].isCollapsed { toggleSplit() }
        window.makeFirstResponder(left.table)
    }
    @objc func openWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let saved = WorkspaceStore.shared.items.first(where: { $0.id.uuidString == id }) else { return }
        restoreWorkspace(saved)
    }
    @objc func removeWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let a = NSAlert(); a.messageText = "Arbeitsbereich „\(sender.title)“ entfernen?"; a.informativeText = "Nur die gespeicherte Ansicht wird entfernt. Deine Dateien bleiben erhalten."; a.addButton(withTitle: "Entfernen"); a.addButton(withTitle: "Abbrechen")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        WorkspaceStore.shared.items = WorkspaceStore.shared.items.filter { $0.id.uuidString != id }; rebuildWorkspaces()
    }
}
