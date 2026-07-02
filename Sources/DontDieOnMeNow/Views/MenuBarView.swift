import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: PowerSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 14) {
                if let activeSessionValue = store.activeSessionValue {
                    timerBlock(value: activeSessionValue, caption: store.activeSessionCaption)
                } else if isReady {
                    durationPicker
                }

                primaryButton

                if store.snapshot.sleepSetting.isDisabled {
                    Label("Use a hard, ventilated surface.", systemImage: "thermometer.medium")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage = store.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 18)

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.2), value: store.statusMessage)
        .onAppear {
            store.refresh()
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
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: store.menuBarSystemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(store.statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(store.statusDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    private func timerBlock(value: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: value.count > 8 ? 28 : 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let caption {
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DURATION")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)

            durationChips

            if store.selectedDuration == .custom {
                customDurationEditor
            }
        }
        .disabled(store.isWorking)
    }

    private var durationChips: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(AwakeDuration.allCases) { duration in
                durationChip(duration)
            }
        }
    }

    private func durationChip(_ duration: AwakeDuration) -> some View {
        let isSelected = store.selectedDuration == duration

        return Button {
            store.setSelectedDuration(duration)
        } label: {
            Text(duration.chipLabel)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(duration.label)
    }

    private var customDurationEditor: some View {
        HStack(spacing: 8) {
            TextField(
                "Minutes",
                value: Binding(
                    get: { store.customDurationMinutes },
                    set: { store.setCustomDurationMinutes($0) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)

            Stepper(
                "",
                value: Binding(
                    get: { store.customDurationMinutes },
                    set: { store.setCustomDurationMinutes($0) }
                ),
                in: store.customDurationBounds,
                step: 5
            )
            .labelsHidden()
            .fixedSize()

            Spacer()

            Text(store.customDurationLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var primaryButton: some View {
        Button {
            store.performPrimaryAction()
        } label: {
            HStack(spacing: 6) {
                if store.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: store.actionSystemImage)
                }
                Text(store.actionTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .tint(isStopAction ? .red : .accentColor)
        .controlSize(.large)
        .disabled(store.isWorking)
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
    }

    private var isReady: Bool {
        if case .normal = store.snapshot.sleepSetting {
            return true
        }
        return false
    }

    private var isStopAction: Bool {
        store.snapshot.sleepSetting.isDisabled
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

private extension AwakeDuration {
    var chipLabel: String {
        switch self {
        case .oneHour:
            return "1h"
        case .threeHours:
            return "3h"
        case .sixHours:
            return "6h"
        case .twelveHours:
            return "12h"
        case .custom:
            return "Custom"
        case .indefinite:
            return "∞"
        }
    }
}
