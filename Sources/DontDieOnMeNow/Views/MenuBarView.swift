import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: PowerSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: store.menuBarSystemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(store.snapshot.sleepSetting.isDisabled ? .orange : .secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.statusTitle)
                        .font(.headline)
                    Text(store.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                store.performPrimaryAction()
            } label: {
                HStack {
                    Image(systemName: store.actionSystemImage)
                    Text(store.actionTitle)
                    Spacer()
                    if store.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(store.isWorking)

            Picker(
                "Duration",
                selection: Binding(
                    get: { store.selectedDuration },
                    set: { store.setSelectedDuration($0) }
                )
            ) {
                ForEach(AwakeDuration.allCases) { duration in
                    Text(duration.label).tag(duration)
                }
            }
            .pickerStyle(.menu)
            .disabled(store.isWorking)

            Text(store.sessionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.canRestartTimer {
                Button {
                    store.startAwakeSession()
                } label: {
                    HStack {
                        Image(systemName: store.selectedDuration == .indefinite ? "infinity.circle" : "timer")
                        Text("Restart Timer")
                    }
                }
                .disabled(store.isWorking)
            }

            if let statusMessage = store.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Keep the Mac on a hard, ventilated surface when sleep is disabled.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Refresh") {
                    store.refresh()
                }
                .disabled(store.isWorking)

                Button("About") {
                    AboutPanel.show()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            store.refresh()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            store.tick()
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
