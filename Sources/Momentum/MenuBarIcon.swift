import AppKit

/// Custom menu bar glyph: a swoosh sweeping through a circle. Distinct from
/// macOS's stock headphones icon (which the system Sound control also shows for
/// the Momentum 4). Rendered as a template image so it adapts to light/dark and
/// the active-highlight state.
enum MenuBarIcon {
    static let image: NSImage = render()

    private static func render() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setStrokeColor(NSColor.black.cgColor)   // template -> tinted by the system
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Circle
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: CGRect(x: 1.6, y: 1.6, width: 14.8, height: 14.8))  // centre (9,9), r 7.4

            // Swoosh sweeping through the centre
            ctx.setLineWidth(1.8)
            ctx.move(to: CGPoint(x: 4.7, y: 7.7))
            ctx.addCurve(to: CGPoint(x: 13.3, y: 10.3),
                         control1: CGPoint(x: 7.6, y: 12.2),
                         control2: CGPoint(x: 10.4, y: 5.8))
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
