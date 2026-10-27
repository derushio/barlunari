import AppKit

/// 設定のウインドウで、⌘W と ⌘Q と編集のショートカットを使えるようにする最小のメニュー。アプリが前面になっている間だけ、メニューバーに出る。
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenuItem(title: "Barlunari", items: [
            NSMenuItem(title: "Barlunari を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        main.addItem(submenuItem(title: "編集", items: [
            NSMenuItem(title: "取り消す", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "切り取り", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        main.addItem(submenuItem(title: "ウインドウ", items: [
            NSMenuItem(title: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
            NSMenuItem(title: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        ]))
        return main
    }

    private static func submenuItem(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
