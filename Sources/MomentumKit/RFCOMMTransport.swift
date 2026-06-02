import Foundation
import IOBluetooth
import CoreBluetooth   // only for the non-blocking CBManager.authorization status read
import os

/// Owns the Bluetooth Classic RFCOMM link to the Momentum 4 and exchanges GAIA
/// packets over it.
///
/// All `IOBluetooth` work runs on a dedicated thread with its own CFRunLoop that
/// is pumped continuously in the default mode. This is required because a SwiftUI
/// app's main run loop does not service the run-loop source that
/// `openRFCOMMChannelAsync` installs, so the open-complete callback would never
/// fire if the work were done on main. Results are marshalled back to the main
/// queue via the `on…` callbacks.
public final class RFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {

    static let log = Logger(subsystem: "io.bransfer.momentum", category: "rfcomm")

    public enum State: Equatable { case disconnected, connecting, connected }

    /// Mutated only on the Bluetooth thread; observers are notified on main.
    public private(set) var state: State = .disconnected {
        didSet {
            guard state != oldValue else { return }
            let snapshot = state
            DispatchQueue.main.async { [weak self] in self?.onStateChange?(snapshot) }
        }
    }

    /// Fired on the main queue when the link state changes.
    public var onStateChange: ((State) -> Void)?
    /// Fired on the main queue for each fully-framed inbound GAIA packet.
    public var onPacket: ((GAIAPacket) -> Void)?
    /// Fired on the main queue when the user has denied Bluetooth permission.
    public var onAuthorizationDenied: (() -> Void)?
    /// Human-readable name of the connected device, if known.
    public private(set) var deviceName: String?

    private let nameNeedle: String
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var rxBuffer: [UInt8] = []
    private var reconnectTimer: Timer?
    private var watchdog: Timer?

    private var btThread: Thread?
    private let runLoopLock = NSLock()
    private var btRunLoop: CFRunLoop?

    public init(nameContains: String = "momentum") {
        self.nameNeedle = nameContains.lowercased()
        super.init()
    }

    // MARK: - Public API (called from main, hops to the Bluetooth thread)

    public func start() {
        ensureThread()
        runOnBT { [weak self] in self?.connectOnBT() }
    }

    public func connect() {
        ensureThread()
        runOnBT { [weak self] in self?.connectOnBT() }
    }

    public func disconnect() {
        runOnBT { [weak self] in self?.teardown() }
    }

    /// Close the channel and block briefly until it is done — for app shutdown,
    /// so the GAIA channel is released cleanly (an abandoned channel wedges the
    /// device's single GAIA connection until Bluetooth is toggled).
    public func disconnectSync(timeout: TimeInterval = 1.0) {
        let semaphore = DispatchSemaphore(value: 0)
        runOnBT { [weak self] in
            self?.teardown()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
    }

    private func teardown() {
        reconnectTimer?.invalidate(); reconnectTimer = nil
        watchdog?.invalidate(); watchdog = nil
        channel?.close()
        channel = nil
        state = .disconnected
    }

    public func send(_ packet: GAIAPacket) {
        runOnBT { [weak self] in self?.sendOnBT(packet) }
    }

    // MARK: - Bluetooth thread

    private func ensureThread() {
        guard btThread == nil else { return }
        let thread = Thread { [weak self] in self?.threadMain() }
        thread.name = "io.bransfer.momentum.bt"
        thread.stackSize = 1 << 20
        btThread = thread
        thread.start()
    }

    private func threadMain() {
        runLoopLock.lock()
        btRunLoop = CFRunLoopGetCurrent()
        runLoopLock.unlock()
        // A persistent port source keeps the run loop from exiting when idle.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        Diag.write("BT thread run loop started")
        while !Thread.current.isCancelled {
            CFRunLoopRunInMode(.defaultMode, 1.0, false)
        }
    }

    private func runOnBT(_ block: @escaping () -> Void) {
        runLoopLock.lock()
        let runLoop = btRunLoop
        runLoopLock.unlock()
        guard let runLoop else {   // thread still booting; retry shortly
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.runOnBT(block) }
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - Connect (Bluetooth thread)

    private func connectOnBT() {
        guard state == .disconnected else { return }   // one attempt at a time

        Diag.write("connect() authorization=\(CBManager.authorization.rawValue)")
        switch CBManager.authorization {
        case .denied, .restricted:
            Self.log.error("bluetooth permission denied/restricted")
            Diag.write("connect() -> permission denied/restricted")
            state = .disconnected
            DispatchQueue.main.async { [weak self] in self?.onAuthorizationDenied?() }
            return
        default:
            break   // .notDetermined -> the pairedDevices() call below raises the prompt
        }

        guard let found = findDevice() else {
            Diag.write("connect() -> no Momentum device found")
            scheduleReconnect(); return
        }
        deviceName = found.name
        guard found.isConnected() else {
            Diag.write("device not audio-connected; will retry")
            scheduleReconnect(); return
        }
        // Re-create a fresh device handle by address (matches a known-good path).
        guard let addr = found.addressString, let dev = IOBluetoothDevice(addressString: addr) else {
            Diag.write("could not recreate device by address")
            failConnect(); return
        }
        device = dev
        state = .connecting
        armWatchdog()
        Diag.write("SDP query on \(addr)")
        if dev.performSDPQuery(self) != kIOReturnSuccess { failConnect() }
    }

    private func findDevice() -> IOBluetoothDevice? {
        // First call here surfaces the macOS Bluetooth permission prompt.
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            Diag.write("pairedDevices() returned nil")
            return nil
        }
        Diag.write("pairedDevices: \(paired.count)")
        return paired.first { ($0.name ?? "").lowercased().contains(nameNeedle) && $0.isConnected() }
            ?? paired.first { ($0.name ?? "").lowercased().contains(nameNeedle) }
    }

    @objc func sdpQueryComplete(_ dev: IOBluetoothDevice!, status: IOReturn) {
        guard state == .connecting else { return }
        guard status == kIOReturnSuccess,
              let records = dev.services as? [IOBluetoothSDPServiceRecord] else {
            Diag.write("sdp query failed status=\(status)")
            failConnect(); return
        }
        guard let gaiaChannel = Self.findGAIAChannel(in: records) else {
            Diag.write("no GAIA RFCOMM channel among \(records.count) services")
            failConnect(); return
        }
        Diag.write("opening GAIA on RFCOMM channel \(gaiaChannel)")
        var opened: IOBluetoothRFCOMMChannel?
        let result = dev.openRFCOMMChannelAsync(&opened, withChannelID: gaiaChannel, delegate: self)
        Diag.write("openRFCOMMChannelAsync result=\(result) gotChannel=\(opened != nil)")
        channel = opened   // retain the channel object while the open completes
        if result != kIOReturnSuccess { failConnect() }
    }

    /// The M4 advertises GAIA as a service literally named "GAIA" (not standard
    /// SPP). Fall back to any RFCOMM channel that is not a hands-free/audio profile.
    static func findGAIAChannel(in records: [IOBluetoothSDPServiceRecord]) -> BluetoothRFCOMMChannelID? {
        var fallback: BluetoothRFCOMMChannelID?
        for record in records {
            var ch: BluetoothRFCOMMChannelID = 0
            guard record.getRFCOMMChannelID(&ch) == kIOReturnSuccess else { continue }
            let name = (record.getServiceName() ?? "").lowercased()
            if name == "gaia" { return ch }
            if !name.contains("hands") && !name.contains("headset") && !name.contains("audio") {
                fallback = ch
            }
        }
        return fallback
    }

    // MARK: - RFCOMM delegate (Bluetooth thread)

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        Diag.write("rfcommChannelOpenComplete status=\(error)")
        watchdog?.invalidate(); watchdog = nil
        guard error == kIOReturnSuccess else {
            Diag.write("rfcomm open failed status=\(error)")
            failConnect(); return
        }
        channel = rfcommChannel
        rxBuffer.removeAll(keepingCapacity: true)
        Diag.write("rfcomm channel open, mtu=\(rfcommChannel.getMTU()) — CONNECTED")
        state = .connected
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard dataLength > 0 else { return }
        let chunk = UnsafeRawBufferPointer(start: dataPointer, count: dataLength)
        Diag.write("rx \(dataLength) bytes: \(chunk.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))")
        rxBuffer.append(contentsOf: chunk)
        let (packets, remainder) = GAIAPacket.split(rxBuffer)
        rxBuffer = remainder
        for packet in packets {
            DispatchQueue.main.async { [weak self] in self?.onPacket?(packet) }
        }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        if state != .disconnected {
            Diag.write("rfcomm channel closed")
            state = .disconnected
            scheduleReconnect()
        }
    }

    private func sendOnBT(_ packet: GAIAPacket) {
        guard let channel, channel.isOpen() else { return }
        var bytes = packet.encoded()
        let length = UInt16(bytes.count)
        bytes.withUnsafeMutableBytes { raw in
            _ = channel.writeSync(raw.baseAddress, length: length)
        }
    }

    // MARK: - Reconnection (Bluetooth thread)

    private func failConnect() {
        Diag.write("failConnect()")
        watchdog?.invalidate(); watchdog = nil
        channel?.close()
        channel = nil
        state = .disconnected
        scheduleReconnect()
    }

    private func scheduleReconnect(after seconds: TimeInterval = 4.0) {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.connectOnBT()
        }
    }

    private func armWatchdog(after seconds: TimeInterval = 12.0) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.state == .connecting else { return }
            Diag.write("connect watchdog fired")
            self.failConnect()
        }
    }
}
