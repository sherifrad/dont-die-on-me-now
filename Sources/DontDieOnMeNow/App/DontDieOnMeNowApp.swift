import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct DontDieOnMeNowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PowerSettingsStore(client: .live)

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.menuBarSystemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(store.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
