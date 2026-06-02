import Foundation

/// Momentum 4 GAIA command map. Values validated live against the device on
/// 2026-06-01 and cross-checked with the `m4.json` definition from the
/// open-source Sennheiser desktop client.
public enum M4 {
    /// Sennheiser/Sonova GAIA vendor ID.
    public static let vendorID: UInt16 = 0x0495

    /// GAIA command IDs. Each feature has a GET command whose response echoes
    /// the value, and a SET command whose response carries no payload.
    public enum Cmd {
        // ANC engine on/off
        public static let ancStatusGet: UInt16 = 0x1A05
        public static let ancStatusResp: UInt16 = 0x1B05
        public static let ancStatusSet: UInt16 = 0x1A04

        // Transparency / hear-through intensity (UInt8 level) — drives the slider
        public static let transparencyGet: UInt16 = 0x1A03
        public static let transparencyResp: UInt16 = 0x1B03
        public static let transparencySet: UInt16 = 0x1A02

        // ANC sub-modes: response is 3×(mode,state); set takes a single (mode,state)
        public static let ancGet: UInt16 = 0x1A01
        public static let ancResp: UInt16 = 0x1B01
        public static let ancSet: UInt16 = 0x1A00

        // Transparent-hearing on/off (distinct from ANC status)
        public static let transHearingStatusGet: UInt16 = 0x1805
        public static let transHearingStatusResp: UInt16 = 0x1905
        public static let transHearingStatusSet: UInt16 = 0x1804

        // Read-only info
        public static let modelGet: UInt16 = 0x1206
        public static let modelResp: UInt16 = 0x1306
        public static let batteryGet: UInt16 = 0x0603
        public static let batteryResp: UInt16 = 0x0703
        public static let codecGet: UInt16 = 0x0800
        public static let codecResp: UInt16 = 0x0900
        public static let firmwareGet: UInt16 = 0x1201
        public static let firmwareResp: UInt16 = 0x1301
    }

    /// Audio codec names indexed by the `Sound_CodecUsed` byte. Returns "" for
    /// out-of-range values (e.g. 0xFF, reported when no stream is active) so the
    /// UI can simply omit it.
    public static func codecName(_ value: UInt8) -> String {
        let names = ["SBC", "AAC", "aptX", "aptX LL", "MP3", "aptX HD",
                     "Faststream", "LHDC", "aptX Adaptive", "aptX Lossless"]
        return Int(value) < names.count ? names[Int(value)] : ""
    }

    /// `mode` byte used inside the ANC sub-mode set/response payload.
    public enum ANCMode {
        public static let antiWind: UInt8 = 0x01
        public static let comfort: UInt8 = 0x02
        public static let adaptive: UInt8 = 0x03
    }

    // Convenience builders ----------------------------------------------------

    public static func get(_ command: UInt16) -> GAIAPacket {
        GAIAPacket(vendorID: vendorID, commandID: command)
    }

    public static func set(_ command: UInt16, _ payload: [UInt8]) -> GAIAPacket {
        GAIAPacket(vendorID: vendorID, commandID: command, payload: payload)
    }
}
