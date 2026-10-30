import AppKit
import Quartz

final class PreviewWindow: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        // Quick Look's embedded viewers may consume keys before keyDown reaches the panel.
        if event.type == .keyDown && FilePreview.shared.handleKeyEvent(event) { return }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { close() }
}
final class FilePreview: NSObject, NSWindowDelegate {
    static let shared = FilePreview()
    private var panel: PreviewWindow?
    private var preview: QLPreviewView?
    private weak var navigationTable: NSTableView?
    private(set) var url: URL?
    var isVisible: Bool { panel?.isVisible ?? false }
    func close() { panel?.close() }
    func toggle(_ item: URL?, sourceTable: NSTableView? = nil) {
        if isVisible { close(); return }
        guard let item else { return }; show(item,sourceTable:sourceTable)
    }
    func show(_ item: URL, sourceTable: NSTableView? = nil) {
        if panel == nil {
            let p = PreviewWindow(contentRect: NSRect(x: 0,y: 0,width: 760,height: 620), styleMask: [.titled,.closable,.resizable,.utilityWindow], backing: .buffered, defer: false)
            p.isReleasedWhenClosed = false; p.minSize = NSSize(width: 400,height: 300); p.delegate = self; p.title = "Vorschau"
            let q = QLPreviewView(frame: p.contentView!.bounds, style: .normal)!
            q.autoresizingMask = [.width,.height]; q.shouldCloseWithWindow = false
            p.contentView = q; preview = q; panel = p; p.center()
        }
        navigationTable = sourceTable
        url = item; panel?.title = item.lastPathComponent + " — Vorschau"; preview?.previewItem = item as NSURL
        if let sourceTable {
            sourceTable.window?.makeFirstResponder(sourceTable)
            panel?.orderFront(nil)
        } else { panel?.makeKeyAndOrderFront(nil) }
    }
    func update(_ item: URL?, sourceTable: NSTableView? = nil) {
        guard isVisible else { return }
        if let sourceTable, sourceTable !== navigationTable {
            // An unrelated pane refresh must not dismiss or replace this preview.
            guard sourceTable.window?.firstResponder === sourceTable, item != nil else { return }
            navigationTable = sourceTable
        }
        guard let item else { close(); return }
        url = item; panel?.title = item.lastPathComponent + " — Vorschau"; preview?.previewItem = item as NSURL
    }
    @discardableResult func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isVisible, event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty else { return false }
        if event.keyCode == 49 || event.keyCode == 53 { close(); return true }
        guard event.keyCode == 125 || event.keyCode == 126, let table = navigationTable else { return false }
        guard table.numberOfRows > 0 else { return true }
        let step = event.keyCode == 125 ? 1 : -1
        let next = table.selectedRow < 0 ? 0 : min(table.numberOfRows-1,max(0,table.selectedRow+step))
        table.selectRowIndexes(IndexSet(integer:next),byExtendingSelection:false)
        table.scrollRowToVisible(next)
        return true
    }
    func windowWillClose(_ notification: Notification) {
        preview?.previewItem = nil; url = nil
        let table = navigationTable; navigationTable = nil
        if panel?.isKeyWindow == true { table?.window?.makeKeyAndOrderFront(nil); table?.window?.makeFirstResponder(table) }
    }
}
