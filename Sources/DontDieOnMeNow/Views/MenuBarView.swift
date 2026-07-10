import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: PowerSettingsStore
    @State private var customMinutesText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isReady {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                Divider()
                    .padding(.horizontal, 18)
            }

            VStack(alignment: .leading, spacing: 14) {
                if let activeSessionValue = store.activeSessionValue {
                    timerBlock(value: activeSessionValue, caption: store.activeSessionCaption)
                } else if isReady {
                    readyControls
                }

                if !isReady {
                    primaryButton
                }

                if store.snapshot.sleepSetting.isDisabled {
                    Label("Use a hard, ventilated surface.", systemImage: "thermometer.medium")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage = store.statusMessage, !isReady {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, isReady ? 12 : 14)
            .padding(.bottom, 12)

            if !store.snapshot.sleepSetting.isDisabled {
                Divider()
                    .padding(.horizontal, 18)

                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
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
                MenuBarStatusIcon(icon: store.menuBarIcon, size: 20)
                    .foregroundStyle(statusColor)
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

    private var readyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            presetButtons
            customDurationRow

            if store.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: parsedCustomMinutes)
    }

    private var presetButtons: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(AwakeDuration.visiblePresets) { duration in
                startButton(duration)
            }
        }
    }

    private var customDurationRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                startButton(.indefinite)
                customDurationField
            }

            if let customMinutes = parsedCustomMinutes {
                Button {
                    startCustomSession(minutes: customMinutes)
                } label: {
                    Text("Start")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(store.isWorking)
                .accessibilityLabel("Start custom awake session")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var customDurationField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            TextField("Custom", text: $customMinutesText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .disabled(store.isWorking)
                .accessibilityLabel("Custom duration in minutes")
                .accessibilityHint("Enter 5 to 1440 minutes")
                .onSubmit {
                    if let customMinutes = parsedCustomMinutes {
                        startCustomSession(minutes: customMinutes)
                    }
                }
                .onChange(of: customMinutesText) { newValue in
                    updateCustomMinutesInput(newValue)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .help("Custom minutes")
    }

    private func startButton(_ duration: AwakeDuration) -> some View {
        Button {
            store.startAwakeSession(duration: duration)
        } label: {
            Text(duration.compactLabel)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(store.isWorking)
        .accessibilityLabel("Keep awake \(duration.label)")
        .help(duration.label)
    }

    private var parsedCustomMinutes: Int? {
        let trimmedValue = customMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let minutes = Int(trimmedValue),
              store.customDurationBounds.contains(minutes) else {
            return nil
        }

        return minutes
    }

    private func updateCustomMinutesInput(_ value: String) {
        let digitsOnly = value.filter(\.isWholeNumber)
        if digitsOnly != value {
            customMinutesText = digitsOnly
            return
        }

        if let customMinutes = parsedCustomMinutes {
            store.setSelectedDuration(.custom)
            store.setCustomDurationMinutes(customMinutes)
        }
    }

    private func startCustomSession(minutes: Int) {
        store.setCustomDurationMinutes(minutes)
        store.startAwakeSession(duration: .custom)
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
