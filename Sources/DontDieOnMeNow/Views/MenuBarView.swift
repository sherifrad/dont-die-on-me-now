import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: PowerSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let activeSessionValue = store.activeSessionValue {
                timerBlock(value: activeSessionValue, caption: store.activeSessionCaption)
            } else if isReady {
                durationPicker
            }

            primaryButton

            if store.snapshot.sleepSetting.isDisabled {
                Text("Use a hard, ventilated surface.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage = store.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: store.menuBarSystemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.statusTitle)
                    .font(.headline)
                Text(store.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timerBlock(value: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: value.count > 8 ? 30 : 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let caption {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var durationPicker: some View {
        HStack(spacing: 10) {
            Text("Duration")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
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
            .frame(width: 168)
        }
        .disabled(store.isWorking)
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

    private var isReady: Bool {
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
            return .secondary
        }
    }
}
