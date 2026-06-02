import Foundation

/// The three top-level noise-control modes, mirroring Sennheiser's Smart Control app.
public enum NoiseMode: String, CaseIterable, Identifiable, Equatable {
    case adaptive   // ANC auto-adjusts to the environment
    case custom     // manual ANC <-> Transparency via the slider
    case off        // neither ANC nor transparency

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .adaptive: return "Adaptive"
        case .custom:   return "Custom"
        case .off:      return "Off"
        }
    }

    public var systemImage: String {
        switch self {
        case .adaptive: return "wand.and.rays"
        case .custom:   return "slider.horizontal.3"
        case .off:      return "minus.circle"
        }
    }
}

/// Maps the bidirectional Custom slider to the device's `ANC_Transparency` byte.
///
/// The value runs 0...100: `0` = maximum ANC, `50` = neutral (no processing),
/// `100` = full transparency. The two ends are shown as "ANC X%" / "X% Transparency"
/// measured from the centre — exactly like the official app.
public enum NoiseControl {
    public static let min = 0
    public static let neutral = 50
    public static let max = 100

    public static func ancPercent(_ value: Int) -> Int {
        Swift.max(0, (neutral - value) * 2)        // value 0 -> 100%, value 50 -> 0%
    }

    public static func transparencyPercent(_ value: Int) -> Int {
        Swift.max(0, (value - neutral) * 2)        // value 100 -> 100%, value 50 -> 0%
    }

    public static func clamp(_ value: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}
