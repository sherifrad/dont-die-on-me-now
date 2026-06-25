import AppKit

enum AboutPanel {
    static func show() {
        let alert = NSAlert()
        alert.messageText = "Don't Die On Me Now"
        alert.informativeText = "A tiny macOS menu bar utility for keeping Codex and Claude Code running while your MacBook lid is closed. It only toggles pmset disablesleep and stores no credentials."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

