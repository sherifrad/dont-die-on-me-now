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
    @StateObject private var store = PowerSettingsStore(
        client: .live,
        automaticallyTicks: true,
        refreshOnStart: true
    )

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            HStack(spacing: 4) {
                MenuBarStatusIcon(icon: store.menuBarIcon, size: 18)
                if let menuBarTitle = store.menuBarTitle {
                    Text(menuBarTitle)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(store.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
