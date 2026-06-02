import Foundation
import Combine
import os

/// High-level, observable controller for the Momentum 4. Bridges the raw GAIA
/// transport to SwiftUI state and exposes the unified-slider semantics.
public final class M4Controller: ObservableObject {

    static let log = Logger(subsystem: "io.bransfer.momentum", category: "controller")

    // Connection
    @Published public private(set) var connectionState: RFCOMMTransport.State = .disconnected
    @Published public private(set) var deviceName: String = "Momentum 4"
    @Published public private(set) var permissionDenied: Bool = false

    // Device state (mirrors the headphones)
    @Published public private(set) var ancOn: Bool = false
    @Published public private(set) var transparencyLevel: UInt8 = 0
    @Published public private(set) var transparentHearingOn: Bool = false
    @Published public private(set) var adaptive: Bool = false
    @Published public private(set) var antiWind: UInt8 = 0
    @Published public private(set) var comfort: Bool = false
    @Published public private(set) var battery: Int? = nil
    @Published public private(set) var codec: String = ""
    @Published public private(set) var firmware: String = ""
    @Published public private(set) var modelID: String = ""

    private let transport: RFCOMMTransport
    private var refreshTimer: Timer?

    /// While `Date() < suppressReadsUntil`, incoming GET responses for
    /// user-controllable values are ignored, so a stale background poll can't
    /// revert a change the user just made before the device finishes applying it.
    /// Read-only info (battery/codec/firmware/model) is never suppressed.
    private var suppressReadsUntil = Date.distantPast
    private let writeSuppressionWindow: TimeInterval = 3.0

    public init(transport: RFCOMMTransport = RFCOMMTransport()) {
        self.transport = transport
        self.transport.onStateChange = { [weak self] state in self?.handleState(state) }
        self.transport.onPacket = { [weak self] packet in self?.handle(packet) }
        self.transport.onAuthorizationDenied = { [weak self] in self?.permissionDenied = true }
    }

    public func start() { transport.start() }

    /// Force an immediate reconnect attempt (e.g. from a "Retry" button).
    public func reconnect() { transport.connect() }

    /// Close the GAIA channel cleanly. Call on app termination.
    public func shutdown() { transport.disconnectSync() }

    public var isConnected: Bool { connectionState == .connected }

    // MARK: - Derived noise-control state

    /// Current top-level mode implied by the device state. In Custom the device
    /// keeps ANC on and drives everything from the ANC_Transparency level, so the
    /// mode is simply: ANC off ⇒ Off, adaptive on ⇒ Adaptive, otherwise Custom.
    public var noiseMode: NoiseMode {
        if !ancOn { return .off }
        if adaptive { return .adaptive }
        return .custom
    }

    /// Custom-slider position 0...100 (the device's ANC_Transparency byte).
    public var noiseValue: Int { NoiseControl.clamp(Int(transparencyLevel)) }

    /// SF Symbol for the menu bar item. Intentionally constant — the icon stays
    /// recognizable as "headphones" rather than swapping per mode; connection
    /// state is conveyed by dimming in the label view.
    public var menuBarSymbol: String { "headphones" }

    // MARK: - Commands

    /// Switch the top-level noise-control mode. Mirrors what the device reports
    /// for the official app's Adaptive/Custom/Off: Custom keeps ANC on with
    /// adaptive off and leaves the ANC_Transparency level untouched.
    public func setNoiseMode(_ mode: NoiseMode) {
        switch mode {
        case .adaptive:
            setANC(true)
            setAdaptive(true)
        case .custom:
            setAdaptive(false)
            setANC(true)
        case .off:
            setANC(false)
        }
    }

    /// Set the Custom-mode slider position (0...100). Custom is driven *entirely*
    /// by the ANC_Transparency level — the device manages its own ANC↔transparency
    /// blend from it. We must NOT also toggle TransparentHearing_Status; doing so
    /// overrides the smooth level with a binary on/off (the "only extremes" bug).
    public func setNoiseValue(_ value: Int) {
        setTransparency(UInt8(NoiseControl.clamp(value)))
    }

    /// Send a SET and start the read-suppression window so a stale poll can't
    /// revert this change before the device applies it.
    private func write(_ packet: GAIAPacket) {
        suppressReadsUntil = Date().addingTimeInterval(writeSuppressionWindow)
        transport.send(packet)
    }

    public func setANC(_ on: Bool) {
        ancOn = on
        write(M4.set(M4.Cmd.ancStatusSet, [on ? 1 : 0]))
    }

    public func setTransparency(_ level: UInt8) {
        transparencyLevel = level
        write(M4.set(M4.Cmd.transparencySet, [level]))
    }

    public func setTransparentHearing(_ on: Bool) {
        transparentHearingOn = on
        write(M4.set(M4.Cmd.transHearingStatusSet, [on ? 1 : 0]))
    }

    public func setAdaptive(_ on: Bool) {
        adaptive = on
        write(M4.set(M4.Cmd.ancSet, [M4.ANCMode.adaptive, on ? 1 : 0]))
    }

    public func setAntiWind(_ value: UInt8) {
        antiWind = value
        write(M4.set(M4.Cmd.ancSet, [M4.ANCMode.antiWind, value]))
    }

    public func setComfort(_ on: Bool) {
        comfort = on
        write(M4.set(M4.Cmd.ancSet, [M4.ANCMode.comfort, on ? 1 : 0]))
    }

    public func refreshAll() {
        for command in [M4.Cmd.ancStatusGet, M4.Cmd.transparencyGet, M4.Cmd.ancGet,
                        M4.Cmd.transHearingStatusGet, M4.Cmd.batteryGet, M4.Cmd.modelGet,
                        M4.Cmd.codecGet, M4.Cmd.firmwareGet] {
            transport.send(M4.get(command))
        }
    }

    // MARK: - Transport plumbing

    private func handleState(_ state: RFCOMMTransport.State) {
        connectionState = state
        if let name = transport.deviceName { deviceName = name }
        Self.log.log("state: \(String(describing: state), privacy: .public)")
        if state == .connected {
            permissionDenied = false
            refreshAll()
            startRefreshTimer()
        } else {
            stopRefreshTimer()
            battery = nil
        }
    }

    private func logState() {
        Diag.write("state mode=\(noiseMode.label) value=\(noiseValue) anc=\(ancOn) adaptive=\(adaptive) transparency=\(transparencyLevel) hearing=\(transparentHearingOn) antiWind=\(antiWind) battery=\(battery ?? -1) codec=\(codec) fw=\(firmware) model=\(modelID)")
        Self.log.log("""
            mode=\(self.noiseMode.label, privacy: .public) value=\(self.noiseValue) \
            anc=\(self.ancOn) adaptive=\(self.adaptive) \
            transparency=\(self.transparencyLevel) hearing=\(self.transparentHearingOn) \
            antiWind=\(self.antiWind) battery=\(self.battery ?? -1)
            """)
    }

    private func handle(_ packet: GAIAPacket) {
        guard packet.vendorID == M4.vendorID else { return }
        let p = packet.payload
        // Ignore controllable values during the post-write window so a stale poll
        // can't revert a change in flight. Read-only info is always accepted.
        let suppressed = Date() < suppressReadsUntil
        switch packet.commandID {
        case M4.Cmd.ancStatusResp:
            if !suppressed, let b = p.first { ancOn = (b == 0x01) }
        case M4.Cmd.transparencyResp:
            if !suppressed, let b = p.first { transparencyLevel = b }
        case M4.Cmd.transHearingStatusResp:
            if !suppressed, let b = p.first { transparentHearingOn = (b == 0x01) }
        case M4.Cmd.ancResp:
            // payload: [mode1,state1, mode2,state2, mode3,state3]
            if !suppressed, p.count >= 6 {
                antiWind = p[1]
                comfort = (p[3] != 0)
                adaptive = (p[5] != 0)
            }
        case M4.Cmd.batteryResp:
            if let b = p.first { battery = Int(b) }
        case M4.Cmd.codecResp:
            if let b = p.first { codec = M4.codecName(b) }
        case M4.Cmd.firmwareResp:
            if p.count >= 6 {
                let major = Int(p[0]) << 8 | Int(p[1])
                let minor = Int(p[2]) << 8 | Int(p[3])
                let patch = Int(p[4]) << 8 | Int(p[5])
                firmware = "\(major).\(minor).\(patch)"
            }
        case M4.Cmd.modelResp:
            let bytes = Array(p.prefix { $0 != 0 })
            if let name = String(bytes: bytes, encoding: .utf8), !name.isEmpty { modelID = name }
        default:
            return
        }
        logState()
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
