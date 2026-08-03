import AppKit

/// Renders the menu bar icon: a bell glyph with an optional unread badge
/// (number or dot) and a warning state for connection/auth errors.
enum BadgeRenderer {
    private static let size = NSSize(width: 22, height: 18)

    static func image(unreadCount: Int, style: BadgeStyle, status: ConnectionStatus) -> NSImage {
        // Error state: a distinct warning glyph (not a template, so the color shows).
        if status != .connected {
            return warningImage()
        }

        let baseSymbol = "bell"
        guard let bell = NSImage(systemSymbolName: baseSymbol, accessibilityDescription: "GitHub notifications") else {
            return NSImage(size: size)
        }

        // No unread → plain template bell that adapts to the menu bar appearance.
        if unreadCount == 0 {
            let img = bell.copy() as! NSImage
            img.isTemplate = true
            return img
        }

        // Unread present → composite bell + badge. Non-template so red is visible.
        let composed = NSImage(size: size)
        composed.lockFocus()

        let bellRect = NSRect(x: 0, y: 0, width: 18, height: 18)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let configured = bell.withSymbolConfiguration(config) {
            configured.isTemplate = true
            // Draw the (black) template glyph, then tint it to the menu bar's
            // label color via sourceAtop so it adapts to light/dark.
            configured.draw(in: bellRect)
            NSColor.labelColor.set()
            bellRect.fill(using: .sourceAtop)
        }

        // Badge is drawn after the tint so it keeps its red fill.
        switch style {
        case .dot:
            drawDot()
        case .number:
            drawCount(unreadCount)
        }

        composed.unlockFocus()
        composed.isTemplate = false
        return composed
    }

    // MARK: - Pieces

    private static func drawDot() {
        let dotRect = NSRect(x: 12, y: 10, width: 8, height: 8)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private static func drawCount(_ count: Int) {
        let text = count > 99 ? "99+" : String(count)
        let badgeHeight: CGFloat = 12
        let font = NSFont.systemFont(ofSize: 9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let badgeWidth = max(badgeHeight, textSize.width + 6)
        let badgeRect = NSRect(
            x: size.width - badgeWidth,
            y: size.height - badgeHeight,
            width: badgeWidth,
            height: badgeHeight
        )
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2).fill()

        let textRect = NSRect(
            x: badgeRect.origin.x + (badgeRect.width - textSize.width) / 2,
            y: badgeRect.origin.y + (badgeRect.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    private static func warningImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(.init(paletteColors: [.systemOrange]))
        let img = NSImage(systemSymbolName: "bell.badge.slash", accessibilityDescription: "GitHub notifications unavailable")?
            .withSymbolConfiguration(config)
            ?? NSImage(size: size)
        img.isTemplate = false
        return img
    }
}
