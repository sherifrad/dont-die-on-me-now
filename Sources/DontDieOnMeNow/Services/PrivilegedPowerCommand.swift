import Foundation

enum PrivilegedPowerCommand {
    static func appleScript(disabled: Bool) -> String {
        let value = disabled ? "1" : "0"
        return "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
    }
}

