import AppKit

func selfTest() throws {
    for question in ["Markiere die größten 3 Dateien hier im Ordner mit der Farbe blau", "Markiere die drei größten Dateien"] {
        let action = BottiSelectionRequest(question); precondition(action.limit == 3 && action.largest && !action.recursive)
    }
    precondition(BottiSelectionRequest("Finde PDFs größer als 20 MB").limit == nil)
    precondition(BottiSelectionRequest("Finde Dateien ohne Unterordner").recursive == false)

    let parsed = try OllamaFileAI.parse(#"{"terms":["Rechnung"],"kind":"pdf","days":-1,"minimumMB":-50,"order":"largest","intent":"find"}"#)
    precondition(parsed.usedAI && parsed.kind == "pdf" && parsed.days == 0 && parsed.minimumBytes == 0)
    for invalid in [#"{"terms":[],"kind":"shell","days":0,"minimumMB":0,"order":"name","intent":"find"}"#, "not JSON"] {
        do { _ = try OllamaFileAI.parse(invalid); preconditionFailure("Invalid model response accepted") } catch { }
    }

    let fixed = BrowserPane.fixedQuickAccess.map { $0.url.path }
    let custom = fm.homeDirectoryForCurrentUser.appendingPathComponent("CustomFavorite").path
    precondition(BrowserPane.mergedFavorites([]) == fixed)
    precondition(BrowserPane.mergedFavorites([fixed[1],custom,custom]) == fixed + [custom])
    precondition(BrowserPane.fixedQuickAccess.map(\.name) == ["Schreibtisch","Downloads","Dokumente","Papierkorb"])

    let screen = NSRect(x:-1440,y:30,width:1440,height:900)
    precondition(WindowPlacement.left.frame(in:screen) == NSRect(x:-1440,y:30,width:720,height:900))
    precondition(WindowPlacement.right.frame(in:screen).maxX == screen.maxX)
    precondition(WindowPlacement.top.frame(in:screen).maxY == screen.maxY)
    precondition(WindowPlacement.bottom.frame(in:screen).minY == screen.minY)
    precondition(WindowPlacement.full.frame(in:screen) == screen)
    precondition(!EjectableVolume.eligible(path:"/",internalDisk:false,local:true,ejectable:true,removable:true))
    precondition(!EjectableVolume.eligible(path:"/Volumes/Internal",internalDisk:true,local:true,ejectable:true,removable:true))
    precondition(!EjectableVolume.eligible(path:"/Volumes/Network",internalDisk:false,local:false,ejectable:false,removable:false))
    precondition(EjectableVolume.eligible(path:"/Volumes/USB",internalDisk:false,local:true,ejectable:false,removable:false))

    let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
    let clipboard = ExplorerClipboard()
    clipboard.write([URL(fileURLWithPath:"/tmp/clipboard-test")],cut:true,pasteboard:pasteboard)
    precondition(clipboard.isCut(pasteboard)); clipboard.consumeCut(); precondition(!clipboard.isCut(pasteboard))
    clipboard.write([URL(fileURLWithPath:"/tmp/clipboard-test")],cut:true,pasteboard:pasteboard)
    pasteboard.clearContents(); pasteboard.setString("anderer Inhalt",forType:.string); precondition(!clipboard.isCut(pasteboard))
    clipboard.write([URL(fileURLWithPath:"/tmp/clipboard-test")],cut:false,pasteboard:pasteboard); precondition(!clipboard.isCut(pasteboard))
    let root = fm.temporaryDirectory.appendingPathComponent("BranchTest-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
    func dir(_ name: String) throws -> URL { let u = root.appendingPathComponent(name); try fm.createDirectory(at: u, withIntermediateDirectories: true); return u }
    func write(_ folder: URL, _ name: String, _ text: String) throws -> URL { let u = folder.appendingPathComponent(name); try Data(text.utf8).write(to: u); return u }
    func content(_ u: URL) throws -> String { try String(contentsOf: u, encoding: .utf8) }
    func expectError(_ body: () throws -> Void) { var blocked = false; do { try body() } catch { blocked = true }; precondition(blocked) }
    let a = try dir("a"), b = try dir("b"), trash = try dir("trash")
    let engine = TransferEngine(trash: { url in let destination = trash.appendingPathComponent(UUID().uuidString); try fm.moveItem(at: url, to: destination); return destination })
    let file = try write(a, "test.txt", "Original")
    let copy = try engine.perform(file, to: b, copy: true, choice: .keepBoth)!
    // Remember each supported choice only within its job, and never bypass same-file protection.
    for choice in [ConflictChoice.keepBoth,.replace,.skip] {
        var memory = ConflictMemory(); var prompts = 0
        for _ in 0..<3 {
            let result = memory.resolve(file,copy.target) { prompts += 1; return ConflictDecision(choice:choice,remember:true) }
            precondition(result == choice)
        }
        precondition(prompts == 1)
        if choice == .replace {
            let result = memory.resolve(file,file) { prompts += 1; return ConflictDecision(choice:.skip,remember:false) }
            precondition(result == .skip && prompts == 2)
        }
        var nextJob = ConflictMemory()
        _ = nextJob.resolve(file,copy.target) { prompts += 1; return ConflictDecision(choice:.keepBoth,remember:false) }
        _ = nextJob.resolve(file,copy.target) { prompts += 1; return ConflictDecision(choice:.skip,remember:false) }
        precondition(prompts == (choice == .replace ? 4 : 3))
    }
    var cancelled = ConflictMemory(); var cancelPrompts = 0
    for _ in 0..<2 { _ = cancelled.resolve(file,copy.target) { cancelPrompts += 1; return ConflictDecision(choice:.cancel,remember:true) } }
    precondition(cancelPrompts == 2)
    let copiedContent = try content(copy.target); precondition(copiedContent == "Original" && TransferEngine.exists(file))
    let duplicate = try engine.perform(file, to: b, copy: true, choice: .keepBoth)!
    precondition(duplicate.target.lastPathComponent == "test (2).txt")
    let skipped = try engine.perform(file, to: b, copy: false, choice: .skip); precondition(skipped == nil && TransferEngine.exists(file))
    let replacedSource = try write(a, "test.txt", "Neu")
    let replacedCopy = try engine.perform(replacedSource, to: b, copy: true, choice: .replace)!
    precondition(replacedCopy.replaced != nil)
    try engine.undo(replacedCopy)
    let restoredContent = try content(b.appendingPathComponent("test.txt")); precondition(restoredContent == "Original")
    try engine.undo(duplicate); precondition(!TransferEngine.exists(duplicate.target))
    try engine.undo(copy); precondition(!TransferEngine.exists(copy.target))
    let moved = try engine.perform(file, to: b, copy: false, choice: .keepBoth)!
    precondition(!TransferEngine.exists(file)); try engine.undo(moved); precondition(TransferEngine.exists(file))
    let oldTarget = try write(b, "test.txt", "Alt")
    let movedReplacing = try engine.perform(file, to: b, copy: false, choice: .replace)!
    try engine.undo(movedReplacing)
    let old = try content(oldTarget); let original = try content(file); precondition(old == "Alt" && original == "Neu")
    expectError { _ = try engine.perform(file, to: a, copy: true, choice: .replace) }
    let sameFolderCopy = try engine.perform(file, to: a, copy: true, choice: .keepBoth)!; precondition(sameFolderCopy.target != file); try engine.undo(sameFolderCopy)
    expectError { _ = try TransferEngine.sources([a], to: a) }
    let child = a.appendingPathComponent("child"); try fm.createDirectory(at: child, withIntermediateDirectories: false)
    expectError { _ = try TransferEngine.sources([a], to: child) }
    let childFile = try write(child, "nested.txt", "Nested")
    let normalized = try TransferEngine.sources([a, childFile, a], to: b); precondition(normalized == [a])
    let folderRecord = try engine.perform(child, to: b, copy: true, choice: .keepBoth)!
    let nested = try content(folderRecord.target.appendingPathComponent("nested.txt")); precondition(nested == "Nested"); try engine.undo(folderRecord)
    let blockedMove = try engine.perform(file, to: b, copy: false, choice: .keepBoth)!
    _ = try write(a, "test.txt", "Neu am Ursprung")
    expectError { try engine.undo(blockedMove) }; precondition(TransferEngine.exists(blockedMove.target))
    try fm.removeItem(at: file); try engine.undo(blockedMove)
    // A failure moving the old target to Trash must restore the moved source.
    let failing = TransferEngine(trash: { _ in throw transferError("simulierter Papierkorbfehler") })
    expectError { _ = try failing.perform(file, to: b, copy: false, choice: .replace) }
    let preservedSource = try content(file); let preservedTarget = try content(oldTarget)
    precondition(preservedSource == "Neu" && preservedTarget == "Alt")
    let remaining = try fm.contentsOfDirectory(atPath: b.path); precondition(remaining.allSatisfy { !$0.hasPrefix(".branch-transfer-") })
    // A target changed during staging must not be overwritten (stable fingerprint primitive).
    let before = TransferEngine.stamp(file); _ = try write(a, "test.txt", "Andere Daten mit anderer Länge"); precondition(before != TransferEngine.stamp(file))
    let systemSource = try dir("SystemSource"), systemTarget = try dir("SystemTarget")
    let systemFile = try write(systemSource, "Branch-Test-" + UUID().uuidString + ".txt", "Neue Testdatei")
    _ = try write(systemTarget, systemFile.lastPathComponent, "Alte Testdatei")
    let systemRecord = try TransferEngine().perform(systemFile, to: systemTarget, copy: true, choice: .replace)!
    guard let trashedOriginal = systemRecord.replaced else { throw transferError("Kein Papierkorbpfad") }
    let trashedContent = try content(trashedOriginal); precondition(trashedContent == "Alte Testdatei")
    try fm.removeItem(at: systemRecord.target); try fm.moveItem(at: trashedOriginal, to: systemRecord.target)
    let saved = SavedWorkspace(id: UUID(), name: "Test", left: PaneSession(tabs: [BrowserTab(path: a.path),BrowserTab(path: b.path)], selected: 1), right: PaneSession(tabs: [BrowserTab(path: b.path)], selected: 0), dual: true)
    let decoded = try JSONDecoder().decode(SavedWorkspace.self, from: JSONEncoder().encode(saved)); precondition(decoded.left.tabs.count == 2 && decoded.left.selected == 1 && decoded.dual)
    precondition(PaneSession(tabs: [],selected: 100).sanitized().selected == 0)
    print("PASS: copy/move; keep both; skip; replace and undo; same-file protection; nested-folder protection; directory copy; undo collisions; failure rollback; macOS Trash and restoration; workspace serialization")
}

func testUIFeatures(_ app: AppDelegate) throws {
    let editMenu = NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Bearbeiten" }
    precondition(editMenu?.items.filter { $0.title == "Ausschneiden" }.count == 1)
    precondition(NSApp.mainMenu?.items.compactMap(\.submenu).contains { $0.title == "Datei" } == true)
    let storedFavorites = app.left.favorites
    app.left.favorites = []
    precondition(app.left.roots.first?.children().map(\.title) == ["Schreibtisch","Downloads","Dokumente","Papierkorb"])
    let trashNode = app.left.roots[0].children()[3]
    precondition(!app.left.outlineView(app.left.outline,isItemExpandable:trashNode))
    app.left.favorites = storedFavorites
    let originalFrame = app.window.frame
    if let screen = app.window.screen {
        for placement in WindowPlacement.allCases {
            let item = NSMenuItem(); item.tag = placement.rawValue; app.placeWindow(item)
            let expected = placement.frame(in:screen.visibleFrame)
            precondition(abs(app.window.frame.width-expected.width) < 2 && abs(app.window.frame.height-expected.height) < 2)
            precondition(abs(app.window.frame.minX-expected.minX) < 2 && abs(app.window.frame.minY-expected.minY) < 2)
        }
        app.window.setFrame(originalFrame,display:true)
        if app.split.splitViewItems[1].isCollapsed { app.toggleSplit() }
    }
    let originalLeft = app.left.session, originalRight = app.right.session
    let originalWorkspaces = WorkspaceStore.shared.items
    defer { app.left.restore(originalLeft); app.right.restore(originalRight); WorkspaceStore.shared.items = originalWorkspaces; app.rebuildWorkspaces() }
    let root = fm.temporaryDirectory.appendingPathComponent("BranchUI-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
    let first = root.appendingPathComponent("Links"), second = root.appendingPathComponent("Rechts")
    try fm.createDirectory(at: first, withIntermediateDirectories: false); try fm.createDirectory(at: second, withIntermediateDirectories: false)
    let sortFixtures = root.appendingPathComponent("Sortierung")
    try fm.createDirectory(at:sortFixtures,withIntermediateDirectories:false)
    let older = sortFixtures.appendingPathComponent("Zuerst.txt"), newer = sortFixtures.appendingPathComponent("Danach.pdf"), third = sortFixtures.appendingPathComponent("NochEine.TXT")
    for (url,date) in [(older,1600000000.0),(newer,1700000000.0),(third,1650000000.0)] {
        try Data("Sortiertest".utf8).write(to:url)
        try fm.setAttributes([.creationDate:Date(timeIntervalSince1970:date)],ofItemAtPath:url.path)
    }
    let createdItem = NSMenuItem(); createdItem.tag = BrowserPane.explorerSortFields.firstIndex { $0.key == "created" }!
    app.right.chooseSort(createdItem)
    precondition(app.right.table.sortDescriptors.first?.key == "created")
    precondition(app.right.sortExplorerFiles([third,older,newer]) == [newer,third,older])
    app.right.chooseSort(createdItem)
    precondition(app.right.sortExplorerFiles([third,older,newer]) == [older,third,newer])
    let typeItem = NSMenuItem(); typeItem.tag = BrowserPane.explorerSortFields.firstIndex { $0.key == "type" }!
    app.right.chooseSort(typeItem)
    let byType = app.right.sortExplorerFiles([third,older,newer]); precondition(byType.first == newer && byType.dropFirst().allSatisfy { $0.pathExtension.lowercased() == "txt" })
    app.right.chooseSort(typeItem); precondition(app.right.sortExplorerFiles([third,older,newer]).last == newer)
    precondition(app.right.table.tableColumns.contains { $0.identifier.rawValue == "created" && $0.sortDescriptorPrototype?.key == "created" })
    app.right.table.sortDescriptors = [NSSortDescriptor(key:"name",ascending:true)]
    let file = first.appendingPathComponent("Vorschau.txt"); try Data("Branch Vorschau\nTextdatei erfolgreich geöffnet.".utf8).write(to: file)
    let nextFile = first.appendingPathComponent("Zweite.txt"); try Data("Zweite Vorschau".utf8).write(to:nextFile)
    app.left.restore(PaneSession(tabs: [BrowserTab(path: first.path)], selected: 0)); let count = app.left.tabs.count
    app.left.newTab(); app.left.navigate(second)
    precondition(app.left.tabs.count == count + 1 && app.left.current.path == second.path)
    app.left.activateTab(count-1); precondition(app.left.current.path == first.path)
    app.left.activateTab(count); precondition(app.left.current.path == second.path)
    app.left.closeTab(at: count); precondition(app.left.tabs.count == count && app.left.current.path == first.path)
    app.left.newTab(); app.left.navigate(second); app.right.navigate(first)
    let workspace = app.snapshotWorkspace(name: "UI Test")
    WorkspaceStore.shared.items = [workspace]; app.rebuildWorkspaces()
    precondition(WorkspaceStore.shared.items.first?.left.tabs.count == count+1)
    app.left.navigate(fm.homeDirectoryForCurrentUser); app.right.navigate(fm.homeDirectoryForCurrentUser)
    app.restoreWorkspace(WorkspaceStore.shared.items[0]); precondition(app.left.current.path == second.path && app.right.current.path == first.path)
    app.right.navigate(second); app.right.goBack(); precondition(app.right.current.path == first.path)
    app.right.goForward(); precondition(app.right.current.path == second.path); app.right.goBack()
    app.right.table.sortDescriptors = [NSSortDescriptor(key:"name",ascending:false)]
    precondition(app.right.visibleFiles.first?.lastPathComponent == "Zweite.txt")
    app.right.table.sortDescriptors = [NSSortDescriptor(key:"name",ascending:true)]
    let descending = NSMenuItem(); descending.tag = 11; app.right.chooseSort(descending)
    precondition(app.right.table.sortDescriptors.first?.ascending == false)
    descending.tag = 10; app.right.chooseSort(descending)
    precondition(app.right.table.sortDescriptors.first?.ascending == true)
    let viewItem = NSMenuItem(); viewItem.tag = 1; app.right.chooseView(viewItem)
    precondition(app.right.table.tableColumns.filter { !$0.isHidden }.count == 1)
    viewItem.tag = 0; app.right.chooseView(viewItem)
    app.right.selectAllFiles(); precondition(app.right.selected.count == 2)
    app.right.invertSelection(); precondition(app.right.selected.isEmpty)
    app.right.invertSelection(); precondition(app.right.selected.count == 2)
    app.right.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: app.window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    app.right.table.keyDown(with: event)
    precondition(FilePreview.shared.isVisible && FilePreview.shared.url?.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
    func arrow(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:app.window.windowNumber,context:nil,characters:code == 125 ? "\u{F701}" : "\u{F700}",charactersIgnoringModifiers:code == 125 ? "\u{F701}" : "\u{F700}",isARepeat:false,keyCode:code)!
    }
    precondition(app.window.firstResponder === app.right.table)
    app.right.table.keyDown(with:arrow(125))
    precondition(FilePreview.shared.isVisible && FilePreview.shared.url?.lastPathComponent == "Zweite.txt" && app.right.table.selectedRow == 1)
    precondition(FilePreview.shared.handleKeyEvent(arrow(126)))
    precondition(FilePreview.shared.isVisible && FilePreview.shared.url?.lastPathComponent == "Vorschau.txt" && app.right.table.selectedRow == 0)
    _ = FilePreview.shared.handleKeyEvent(arrow(126))
    precondition(FilePreview.shared.isVisible && app.right.table.selectedRow == 0)
    FilePreview.shared.update(nil,sourceTable:app.left.table)
    precondition(FilePreview.shared.isVisible)
    app.right.table.keyDown(with: event); precondition(!FilePreview.shared.isVisible)
    // Exercise the real async coordinator without user files or a conflict dialog.
    let center = TransferCenter.shared
    let conflictAlert = center.makeConflictAlert(file,file)
    precondition(conflictAlert.showsSuppressionButton && conflictAlert.suppressionButton?.state == .off)
    precondition(!conflictAlert.buttons[2].isEnabled)
    center.start([file], to: second, copy: true)
    precondition(center.busy && center.status.isHidden)
    let deadline = Date(timeIntervalSinceNow: 10)
    while center.busy && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
    precondition(!center.busy && center.undoButton.isEnabled && center.undoStack.last?.count == 1)
    let transferred = second.appendingPathComponent("Vorschau.txt")
    let content = try String(contentsOf: transferred, encoding: .utf8); precondition(content.contains("Branch Vorschau"))
    print("PASS UI features: tab add/switch/close; workspace save/restore; Space opens/closes Quick Look; async transfer progress and undo registration")
}

func testRobotSearchAndSpeed() throws {
    let root = fm.temporaryDirectory.appendingPathComponent("BranchAssistant-" + UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true); defer { try? fm.removeItem(at:root) }
    let source = root.appendingPathComponent("Quelle"), target = root.appendingPathComponent("Kopie")
    try fm.createDirectory(at:source,withIntermediateDirectories:false)
    let nested = source.appendingPathComponent("Unterordner"); try fm.createDirectory(at:nested,withIntermediateDirectories:false)
    try Data(repeating:0x5a,count:8_000_000).write(to:source.appendingPathComponent("Rechnung.pdf"))
    try Data(repeating:0x33,count:3_000_000).write(to:nested.appendingPathComponent("Foto.jpg"))
    try Data("Besprechung am Montag. Thema: Gartenplanung.".utf8).write(to:source.appendingPathComponent("Notizen.txt"))
    try fm.createSymbolicLink(atPath:source.appendingPathComponent("Verweis").path,withDestinationPath:"Notizen.txt")
    for i in 0..<26 { try Data().write(to:nested.appendingPathComponent("Leer-\(i).txt")) }
    var bytes: Int64 = 0
    let inventory = try TransferInventory.scan(source,stop:StopRequest())
    precondition(inventory.files.count == 30)
    let job = TransferJob(); job.prepare([inventory],now:0)
    var callbacks = Set<String>()
    try copyWithProgress(source,target,fileFinished: { callbacks.insert($0); job.finish($0) }) { bytes += $0; job.add($0) }
    precondition(callbacks.count == 30, "File completions: \(callbacks)")
    let snapshot = job.snapshot(now:1)
    precondition(snapshot.done == 30 && snapshot.total == 30 && snapshot.bytes == inventory.bytes, "Snapshot: \(snapshot); expected \(inventory.files); callbacks \(callbacks)")
    let etaJob = TransferJob(); etaJob.prepare([TransferInventory(files:["a":1000,"b":1000])],now:0)
    etaJob.add(500); _ = etaJob.snapshot(now:0.5)
    etaJob.add(500); let halfway = etaJob.snapshot(now:1)
    precondition(halfway.fraction == 0.5 && halfway.seconds == 1 && halfway.rate == 1000)
    etaJob.skip(TransferInventory(files:["b":1000])); precondition(etaJob.snapshot(now:1).total == 1)
    etaJob.resume(now:2); precondition(etaJob.snapshot(now:2).seconds == nil)
    let stopped = StopRequest(); stopped.request()
    do { _ = try TransferInventory.scan(source,stop:stopped); preconditionFailure("Scan should stop") } catch is CancellationError {}
    let expected = 11_000_000 + (try Data(contentsOf:source.appendingPathComponent("Notizen.txt"))).count
    precondition(bytes == Int64(expected), "Bytezählung: \(bytes) statt \(expected)")
    let link = try fm.destinationOfSymbolicLink(atPath:target.appendingPathComponent("Verweis").path); precondition(link == "Notizen.txt")
    let copiedData = try Data(contentsOf:target.appendingPathComponent("Rechnung.pdf")); precondition(copiedData.count == 8_000_000 && copiedData.first == 0x5a)
    let q = FileQuery(terms:["rechnung"],kind:"pdf",order:"largest")
    let found = FileSearch.search(q,root:source,stop:StopRequest())
    precondition(found.count == 1 && found.totalBytes == 8_000_000 && !found.partial)
    let all = FileSearch.search(FileQuery(),root:source,stop:StopRequest()); precondition(all.count == 29)
    let stop = StopRequest(); stop.request(); precondition(FileSearch.search(FileQuery(),root:source,stop:stop).partial)
    let text = try FileSearch.excerpt(source.appendingPathComponent("Notizen.txt")); precondition(text.contains("Gartenplanung"))
    var unsupported = false; do { _ = try FileSearch.excerpt(nested.appendingPathComponent("Foto.jpg")) } catch { unsupported = true }; precondition(unsupported)
    let state = RobotState.shared; state.searching = true; precondition(state.mood == .thinking)
    state.transferring = true; precondition(state.mood == .working)
    state.searching = false; state.finished(success:true); precondition(state.mood == .happy)
    state.celebrationUntil = .distantPast; precondition(state.mood == .idle && !state.showsBubble)
    for time in [0.0,6.8,18.0,36.5] {
        let idle = RobotPose.at(time,mood:.idle,reduceMotion:false)
        precondition(idle.x == 0 && idle.lift == 0 && idle.angle == 0 && idle.stride == 0 && idle.headTilt == 0)
    }
    precondition(RobotPose.at(1,mood:.working,reduceMotion:false).stride != 0)
    precondition(RobotPose.at(1,mood:.thinking,reduceMotion:false).headTilt != 0)
    for mood in [RobotMood.idle,.working,.thinking,.happy,.concerned] {
        let still = RobotPose.at(1,mood:mood,reduceMotion:true)
        precondition(still.angle == 0 && still.x == 0 && still.lift == 0 && still.headTilt == 0 && still.stride == 0)
    }
    state.searching = true; precondition(state.showsBubble); state.searching = false
    print("PASS: 30-file recursive count including empty files; job-wide bytes, percentage, ETA, pause and skip; measured copy bytes; nested files and symlink preservation; search filtering/counts; cancellation; content extraction; robot states")
}
func testLocalAI() async throws {
    precondition(LocalFileAI.available, "Lokales Modell nicht verfügbar")
    let start = Date()
    let q = await LocalFileAI.query("Zeige mir meine größten PDF-Dateien mit Rechnung im Namen.")
    print("AI query seconds: \(Date().timeIntervalSince(start))")
    print("AI QUERY: kind=\(q.kind), terms=\(q.terms), order=\(q.order), localAI=\(q.usedAI)")
    precondition(q.usedAI && q.kind == "pdf" && q.order == "largest" && q.terms.contains(where:{$0.lowercased().contains("rechnung")}))
    let summary = try await LocalFileAI.summarize("Die Besprechung findet am Dienstag um 10 Uhr statt. Thema ist der neue Garten. Die Rechnung beträgt 250 Euro.",name:"Testnotiz.txt",question:"Wann findet die Besprechung statt?")
    print("AI SUMMARY: \(summary)")
    precondition(summary.lowercased().contains("dienstag") && summary.contains("10"))
    let count = await LocalFileAI.query("Wie viele Bilder habe ich letzte Woche geändert?")
    precondition(count.usedAI && count.kind == "image" && count.days == 7 && count.intent == "count" && count.terms.isEmpty)
    let size = await LocalFileAI.query("Finde PDFs größer als 20 MB.")
    precondition(size.usedAI && size.kind == "pdf" && size.minimumBytes == 20_000_000 && size.terms.isEmpty)
    print("PASS: local AI interprets German file queries and answers from supplied text")
}

@MainActor func testBottiIntegration(_ app: AppDelegate, output:String) async throws {
    let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Botti-Test-" + UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    let folder = root.appendingPathComponent("Testordner")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let child = folder.appendingPathComponent("Unterordner")
    try fm.createDirectory(at:child,withIntermediateDirectories:true)
    for n in 1...4 { try Data(repeating:65,count:n*100).write(to:folder.appendingPathComponent("Datei-\(n).txt")) }
    try Data(repeating:65,count:10000).write(to:child.appendingPathComponent("Nicht-direkt.txt"))
    if app.split.splitViewItems[1].isCollapsed { app.toggleSplit() }
    app.right.navigate(root)
    guard let row = app.right.visibleFiles.firstIndex(where: { $0.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path }) else { throw transferError("Fixture missing: \(app.right.current.path); \(app.right.visibleFiles.map(\.path)); expected \(folder.path)") }
    app.right.table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
    app.window.makeFirstResponder(app.right.table)
    guard FileChat.searchRoot(app.right).resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path else { throw transferError("Wrong search root") }
    let windows = NSApp.windows.count
    app.fileChat.present()
    guard app.activePane === app.right && NSApp.windows.count == windows else { throw transferError("Wrong pane or extra window") }
    await app.fileChat.testCommand("Markiere die größten 3 Dateien hier im Ordner mit der Farbe blau")
    guard app.right.current.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path else { throw transferError("Wrong result folder: \(app.fileChat.testAnswer)") }
    guard Set(app.right.selected.map(\.lastPathComponent)) == Set(["Datei-4.txt","Datei-3.txt","Datei-2.txt"]) else { throw transferError("Wrong selection: \(app.right.selected.map(\.lastPathComponent)); \(app.fileChat.testAnswer)") }
    precondition(app.fileChat.testAnswer.contains("3 größte Dateien"))
    let all = FileSearch.search(FileQuery(),root:folder,stop:StopRequest(),recursive:true)
    precondition(all.count == 5)
    app.window.contentView?.layoutSubtreeIfNeeded()
    if let view = app.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:output + ".botti.png"))
    }
    print("PASS BOTTI: selected folder; right pane retained; exactly 3 largest direct files selected; nested file excluded; no extra window")
}
