import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: PowerSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isNormalSleep {
                durationSection(title: "Duration", detail: durationDetail)
                primaryButton
            } else {
                primaryButton
                sessionSummary

                if store.canRestartTimer {
                    Divider()
                    durationSection(title: "Restart with", detail: restartDurationDetail)
                    restartButton
                }
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
        .padding(16)
        .frame(width: 360)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: store.menuBarSystemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.statusTitle)
                    .font(.headline)
                Text(store.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var primaryButton: some View {
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
        .controlSize(.large)
        .disabled(store.isWorking)
    }

    private func durationSection(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                durationPicker
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var durationPicker: some View {
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
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 170)
        .disabled(store.isWorking)
    }

    private var sessionSummary: some View {
        Text(store.sessionSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var restartButton: some View {
        Button {
            store.startAwakeSession()
        } label: {
            HStack {
                Image(systemName: store.selectedDuration == .indefinite ? "infinity.circle" : "timer")
                Text(store.selectedDuration == .indefinite ? "Restart Session" : "Restart Timer")
                Spacer()
            }
        }
        .buttonStyle(.bordered)
        .disabled(store.isWorking)
    }

    private var isNormalSleep: Bool {
        if case .normal = store.snapshot.sleepSetting {
            return true
        }
        return false
    }

    private var statusColor: Color {
        switch store.snapshot.sleepSetting {
        case .disabled:
            return .orange
        case .normal:
            return .secondary
        case .unknown:
            return .yellow
        }
    }

    private var durationDetail: String {
        if store.selectedDuration == .indefinite {
            return "Keeps the Mac awake until you enable sleep."
        }
        return "Normal sleep restores automatically after \(store.selectedDuration.label)."
    }

    private var restartDurationDetail: String {
        if store.selectedDuration == .indefinite {
            return "Replaces the timer with a manual restore session."
        }
        return "Starts a fresh \(store.selectedDuration.label) timer."
    }
}
