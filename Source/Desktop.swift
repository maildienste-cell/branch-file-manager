import AppKit

enum WindowPlacement: Int, CaseIterable {
    case left, right, top, bottom, full
    var title: String { ["Linke Bildschirmhälfte","Rechte Bildschirmhälfte","Obere Bildschirmhälfte","Untere Bildschirmhälfte","Ganzer Bildschirm"][rawValue] }
    var symbol: String { ["rectangle.lefthalf.filled","rectangle.righthalf.filled","rectangle.tophalf.filled","rectangle.bottomhalf.filled","rectangle.fill"][rawValue] }
    func frame(in screen: NSRect) -> NSRect {
        switch self {
        case .left: return NSRect(x:screen.minX,y:screen.minY,width:floor(screen.width/2),height:screen.height)
        case .right: return NSRect(x:screen.minX+floor(screen.width/2),y:screen.minY,width:ceil(screen.width/2),height:screen.height)
        case .top: return NSRect(x:screen.minX,y:screen.minY+floor(screen.height/2),width:screen.width,height:ceil(screen.height/2))
        case .bottom: return NSRect(x:screen.minX,y:screen.minY,width:screen.width,height:floor(screen.height/2))
        case .full: return screen
        }
    }
}
struct EjectableVolume {
    let url: URL
    let name: String
    static func eligible(path: String, internalDisk: Bool?, local: Bool?, ejectable: Bool?, removable: Bool?) -> Bool {
        guard path.hasPrefix("/Volumes/"), internalDisk != true, local == true else { return false }
        return internalDisk == false || ejectable == true || removable == true
    }
    static func mounted() -> [EjectableVolume] {
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey,.volumeIsLocalKey,.volumeIsEjectableKey,.volumeIsRemovableKey,.volumeNameKey]
        return (fm.mountedVolumeURLs(includingResourceValuesForKeys:Array(keys),options:[]) ?? []).compactMap { url in
            guard let v = try? url.resourceValues(forKeys:keys), eligible(path:url.path,internalDisk:v.volumeIsInternal,local:v.volumeIsLocal,ejectable:v.volumeIsEjectable,removable:v.volumeIsRemovable) else { return nil }
            return EjectableVolume(url:url,name:v.volumeName ?? url.lastPathComponent)
        }
    }
}
extension AppDelegate {
    func desktopActions() -> NSStackView {
        let layout = NSPopUpButton(frame:.zero,pullsDown:true)
        layout.addItem(withTitle:"Layout"); layout.item(at:0)?.image = NSImage(systemSymbolName:"rectangle.split.2x2",accessibilityDescription:nil)
        for position in WindowPlacement.allCases {
            let item = NSMenuItem(title:position.title,action:#selector(placeWindow(_:)),keyEquivalent:"")
            item.tag = position.rawValue; item.target = self; item.image = NSImage(systemSymbolName:position.symbol,accessibilityDescription:nil); layout.menu?.addItem(item)
        }
        layout.toolTip = "Branch auf dem aktuellen Bildschirm anordnen"
        let eject = NSButton(title:"Alle auswerfen",target:self,action:#selector(ejectAllVolumes))
        eject.bezelStyle = .rounded; eject.controlSize = .large
        eject.image = NSImage(systemSymbolName:"eject.circle.fill",accessibilityDescription:"Alle Laufwerke auswerfen")
        eject.symbolConfiguration = NSImage.SymbolConfiguration(pointSize:25,weight:.medium)
        eject.imagePosition = .imageLeading; eject.contentTintColor = BranchStyle.mint
        eject.toolTip = "Alle externen, auswerfbaren Laufwerke sicher auswerfen"
        eject.setAccessibilityLabel("Alle externen Laufwerke auswerfen")
        eject.heightAnchor.constraint(equalToConstant:44).isActive = true
        let row = NSStackView(views:[layout,eject]); row.spacing = 10
        return row
    }
    @objc func placeWindow(_ sender: NSMenuItem) {
        guard let placement = WindowPlacement(rawValue:sender.tag), let screen = window.screen ?? NSScreen.main else { return }
        if window.styleMask.contains(.fullScreen) { pendingPlacement = sender.tag; window.toggleFullScreen(nil); return }
        let target = placement.frame(in:screen.visibleFrame)
        if target.width < 900 && !split.splitViewItems[1].isCollapsed { split.splitViewItems[1].isCollapsed = true; settings.set(false,forKey:"dual"); updateSplitTitle() }
        window.minSize = NSSize(width:min(680,target.width),height:min(390,target.height))
        window.setFrame(target,display:true,animate:false)
        windowDidResize(Notification(name:NSWindow.didResizeNotification,object:window))
    }
    func windowDidResize(_ notification: Notification) {
        if window.frame.height < 650, fileChat.isPresented { fileChat.hide() }
        robot.isHidden = false
        robotHeight?.constant = 92
        robot.needsDisplay = true
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        if let tag = pendingPlacement { pendingPlacement = nil; let item = NSMenuItem(); item.tag = tag; placeWindow(item) }
    }
    @objc func ejectAllVolumes() {
        guard !TransferCenter.shared.busy else { failure("Bitte warte, bis die laufende Dateiaktion abgeschlossen ist."); return }
        let volumes = EjectableVolume.mounted()
        guard !volumes.isEmpty else { TransferCenter.shared.status.stringValue = "Keine auswerfbaren Laufwerke angeschlossen"; return }
        FilePreview.shared.close()
        TransferCenter.shared.setBusy(true); RobotState.shared.transferText = "Laufwerke auswerfen …"
        TransferCenter.shared.stopButton.isHidden = true
        DispatchQueue.global(qos:.userInitiated).async {
            var errors: [String] = []
            for volume in volumes {
                // Ejecting a device can also unmount its other partitions.
                guard fm.fileExists(atPath:volume.url.path) else { continue }
                do { try NSWorkspace.shared.unmountAndEjectDevice(at:volume.url) }
                catch { errors.append("\(volume.name): \(error.localizedDescription)") }
            }
            let problems = errors
            DispatchQueue.main.async {
                TransferCenter.shared.setBusy(false); RobotState.shared.finished(success:problems.isEmpty)
                TransferCenter.shared.status.stringValue = problems.isEmpty ? "Alle auswerfbaren Laufwerke ausgeworfen" : "Nicht alle Laufwerke konnten ausgeworfen werden"
                NotificationCenter.default.post(name:changed,object:nil)
                if !problems.isEmpty { failure(problems.joined(separator:"\n\n")) }
            }
        }
    }
}
