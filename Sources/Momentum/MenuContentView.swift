import SwiftUI
import AppKit
import MomentumKit

struct MenuContentView: View {
    @ObservedObject var controller: M4Controller
    @State private var localValue: Double = 50
    @State private var dragging = false

    private var sliderInt: Int { Int(localValue.rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if controller.permissionDenied {
                rowDivider
                permissionSection.sectionPadding()
            } else if controller.isConnected {
                rowDivider
                noiseControlSection.padding(.vertical, 12)
                if controller.noiseMode == .custom {
                    rowDivider
                    ancOptionsSection.padding(.vertical, 12)
                }
            } else {
                rowDivider
                connectingSection.sectionPadding()
            }

            rowDivider
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 344)
        .background(VisualEffectView(material: .menu, blending: .behindWindow).ignoresSafeArea())
        .onAppear { syncFromDevice() }
        .onChange(of: controller.noiseValue) { _, _ in syncFromDevice() }
        .onChange(of: controller.noiseMode) { _, _ in syncFromDevice() }
    }

    // MARK: - Device header

    private var deviceHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "headphones")
                .font(.system(size: 23))
                .foregroundStyle(.primary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.deviceName.capitalized).font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(controller.isConnected ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let battery = controller.battery {
                HStack(spacing: 4) {
                    Image(systemName: batterySymbol(battery)).imageScale(.large)
                    Text("\(battery)%")
                }
                .font(.subheadline)
                .foregroundStyle(batteryColor(battery))
            }
        }
    }

    private var statusLine: String {
        guard controller.isConnected else {
            return controller.permissionDenied ? "Bluetooth not allowed" : "Searching…"
        }
        var parts = ["Connected"]
        if !controller.codec.isEmpty { parts.append(controller.codec) }
        if !controller.firmware.isEmpty { parts.append("FW \(controller.firmware)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Noise control

    private var noiseControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Noise Control")

            modeSelector

            if controller.noiseMode == .custom {
                customSlider
            } else {
                Text(modeDescription(controller.noiseMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customSlider: some View {
        VStack(spacing: 6) {
            Slider(value: $localValue, in: 0...100, step: 1, onEditingChanged: { editing in
                dragging = editing
                if !editing { controller.setNoiseValue(sliderInt) }
            })
            HStack {
                Text("ANC \(NoiseControl.ancPercent(sliderInt))%")
                    .foregroundStyle(sliderInt < NoiseControl.neutral ? Color.accentColor : .secondary)
                Spacer()
                Text("\(NoiseControl.transparencyPercent(sliderInt))% Transparency")
                    .foregroundStyle(sliderInt > NoiseControl.neutral ? Color.accentColor : .secondary)
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
    }

    /// Custom segmented control whose segments truly fill the width (the native
    /// `.segmented` Picker centers its content under Liquid Glass instead of
    /// stretching). Selected segment uses the accent color.
    private var modeSelector: some View {
        HStack(spacing: 2) {
            ForEach(NoiseMode.allCases) { mode in
                let selected = controller.noiseMode == mode
                Text(mode.label)
                    .font(.callout)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(selected ? Color.accentColor : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { controller.setNoiseMode(mode) }
            }
        }
        .padding(3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func modeDescription(_ mode: NoiseMode) -> String {
        switch mode {
        case .adaptive: return "ANC automatically adapts to your surroundings."
        case .custom:   return "Manually balance noise cancellation and transparency."
        case .off:      return "No noise cancellation or transparency."
        }
    }

    // MARK: - Anti-Wind (Custom mode only, matching the official app)

    private var ancOptionsSection: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Anti-Wind").font(.subheadline).fontWeight(.semibold)
                Text("Reduce wind noise in ANC.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { controller.antiWind > 0 },
                set: { controller.setAntiWind($0 ? 1 : 0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Disconnected / permission

    private var connectingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching for Momentum 4…").font(.callout)
            }
            Text("Make sure the headphones are powered on and connected to this Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Bluetooth permission needed", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
            Text("Allow Bluetooth for Momentum in System Settings, then reopen the app.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Bluetooth Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if !controller.isConnected && !controller.permissionDenied {
                Button("Retry") { controller.reconnect() }
            }
            if !controller.modelID.isEmpty {
                Text(controller.modelID).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    // MARK: - Building blocks

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline).fontWeight(.semibold)
            .padding(.horizontal, 16)
    }

    private var rowDivider: some View { Divider().padding(.horizontal, 14) }

    private func syncFromDevice() {
        guard !dragging else { return }
        localValue = Double(controller.noiseValue)
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13:  return "battery.0percent"
        case ..<38:  return "battery.25percent"
        case ..<63:  return "battery.50percent"
        case ..<88:  return "battery.75percent"
        default:     return "battery.100percent"
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        switch level {
        case ..<15: return .red
        case ..<35: return .orange
        default:    return .secondary
        }
    }
}

private extension View {
    func sectionPadding() -> some View {
        self.padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// Native macOS vibrancy background (the translucent "menu" material).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
