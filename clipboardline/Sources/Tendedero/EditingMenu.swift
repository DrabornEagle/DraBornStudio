import AppKit

/// AppKit routes standard editor shortcuts through the main menu, including
/// when a borderless preview panel is key and Library remains the main window.
@MainActor enum EditingMenu {
    private static let tag = 0x434C4544

    static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: L("Edit"))
        let commands = [(L("Undo"), "undo:", "z"), (L("Redo"), "redo:", "z"),
                        (L("Cut"), "cut:", "x"), (L("Copy"), "copy:", "c"),
                        (L("Paste"), "paste:", "v"), (L("Select all"), "selectAll:", "a")]
        for (index, command) in commands.enumerated() {
            let (title, action, key) = command
            if index == 2 || index == 5 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = index == 1 ? [.command, .shift] : .command
            menu.addItem(item)
        }
        return menu
    }

    static func install(onSettings: (() -> Void)? = nil) {
        let root = NSApp.mainMenu ?? NSMenu()
        guard root.item(withTag: tag) == nil else { return }
        if root.items.isEmpty {
            let application = NSMenuItem(title: AppIdentity.name, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: AppIdentity.name)
            let quit = NSMenuItem(title: String(format: L("Quit %@"), AppIdentity.name), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp; menu.addItem(quit); application.submenu = menu
            root.addItem(application)
        }
        if let onSettings, let application = root.items.first?.submenu {
            let settings = ClosureMenuItem(L("Settings…"), key: ",", handler: onSettings)
            application.insertItem(settings, at: 0); application.insertItem(.separator(), at: 1)
        }
        let item = NSMenuItem(title: L("Edit"), action: nil, keyEquivalent: "")
        item.tag = tag; item.submenu = makeMenu()
        root.insertItem(item, at: min(1, root.items.count))
        NSApp.mainMenu = root
    }
}
