import Foundation

/// A single Qualcomm GAIA V3 frame as used by the Sennheiser Momentum 4.
///
/// Wire format (all multi-byte fields big-endian):
/// ```
/// FF 03 [len:2] [vendor:2] [command:2] [payload: len bytes]
/// ```
/// `len` counts only the payload bytes; the total frame length is `8 + len`.
public struct GAIAPacket: Equatable {
    public static let startOfFrame: UInt8 = 0xFF
    public static let version: UInt8 = 0x03

    public var vendorID: UInt16
    public var commandID: UInt16
    public var payload: [UInt8]

    public init(vendorID: UInt16, commandID: UInt16, payload: [UInt8] = []) {
        self.vendorID = vendorID
        self.commandID = commandID
        self.payload = payload
    }

    /// Serialize the packet to its on-the-wire byte representation.
    public func encoded() -> [UInt8] {
        let len = UInt16(truncatingIfNeeded: payload.count)
        var bytes: [UInt8] = [
            GAIAPacket.startOfFrame, GAIAPacket.version,
            UInt8(len >> 8), UInt8(len & 0x00ff),
            UInt8(vendorID >> 8), UInt8(vendorID & 0x00ff),
            UInt8(commandID >> 8), UInt8(commandID & 0x00ff),
        ]
        bytes.append(contentsOf: payload)
        return bytes
    }

    /// Parse exactly one packet from the front of `bytes`.
    /// Returns the packet and the number of bytes consumed, or `nil` if `bytes`
    /// does not begin with a complete, valid frame.
    public static func parse(_ bytes: [UInt8]) -> (packet: GAIAPacket, consumed: Int)? {
        guard bytes.count >= 8 else { return nil }
        guard bytes[0] == startOfFrame, bytes[1] == version else { return nil }
        let len = Int(bytes[2]) << 8 | Int(bytes[3])
        let total = 8 + len
        guard bytes.count >= total else { return nil }
        let vendor = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        let command = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let payload = Array(bytes[8..<total])
        return (GAIAPacket(vendorID: vendor, commandID: command, payload: payload), total)
    }

    /// Split a receive buffer that may contain several concatenated frames
    /// (the M4 commonly glues responses into one RFCOMM read) and/or a trailing
    /// partial frame. Returns the complete packets plus any leftover bytes that
    /// should be prepended to the next read.
    public static func split(_ buffer: [UInt8]) -> (packets: [GAIAPacket], remainder: [UInt8]) {
        var packets: [GAIAPacket] = []
        var i = 0
        let n = buffer.count
        while i < n {
            // Need at least the 2-byte preamble to decide anything.
            if n - i < 2 { break }
            // Resync if we are not sitting on a frame boundary.
            if buffer[i] != startOfFrame || buffer[i + 1] != version {
                i += 1
                continue
            }
            if n - i < 8 { break }                       // header not fully arrived yet
            let len = Int(buffer[i + 2]) << 8 | Int(buffer[i + 3])
            let total = 8 + len
            if n - i < total { break }                   // payload not fully arrived yet
            let vendor = UInt16(buffer[i + 4]) << 8 | UInt16(buffer[i + 5])
            let command = UInt16(buffer[i + 6]) << 8 | UInt16(buffer[i + 7])
            let payload = Array(buffer[(i + 8)..<(i + total)])
            packets.append(GAIAPacket(vendorID: vendor, commandID: command, payload: payload))
            i += total
        }
        return (packets, Array(buffer[i...]))
    }
}
