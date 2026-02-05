import Cocoa
import QuickLookThumbnailing

/// Renders custom thumbnails for PGP encrypted files with visual indicators
/// for different encryption types (binary vs ASCII armored)
final class ThumbnailRenderer {

    /// Visual theme for different file encoding formats
    private struct ThumbnailTheme {
        let gradientColors: [CGColor]
        let lockIconName: String
        let accentColor: NSColor
        let badgeColor: NSColor

        /// Theme for binary encoded files (.gpg, .pgp)
        static let binary = ThumbnailTheme(
            gradientColors: [
                NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.93, alpha: 1.0).cgColor
            ],
            lockIconName: "lock.fill",
            accentColor: NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.7, alpha: 1.0),
            badgeColor: NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.7, alpha: 0.9)
        )

        /// Theme for ASCII armored files (.asc)
        static let asciiArmored = ThumbnailTheme(
            gradientColors: [
                NSColor(calibratedRed: 0.95, green: 0.98, blue: 0.96, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.90, alpha: 1.0).cgColor
            ],
            lockIconName: "lock.doc.fill",
            accentColor: NSColor(calibratedRed: 0.2, green: 0.65, blue: 0.4, alpha: 1.0),
            badgeColor: NSColor(calibratedRed: 0.2, green: 0.65, blue: 0.4, alpha: 0.9)
        )
    }

    /// Renders a thumbnail for an encrypted PGP file
    /// - Parameters:
    ///   - result: The analysis result containing file type and encryption info
    ///   - size: The size of the thumbnail to draw
    /// - Returns: True if drawing succeeded, false otherwise
    func renderThumbnail(for result: PGPFileAnalyzer.AnalysisResult, in size: CGSize) -> Bool {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return false
        }

        // Select theme based on encoding format
        let theme = selectTheme(for: result.encodingFormat)

        // Draw background gradient
        drawBackground(context: context, size: size, theme: theme)

        // Draw lock icon
        drawLockIcon(context: context, size: size, theme: theme)

        // Draw "PGP" badge at the bottom
        drawBadge(context: context, size: size, theme: theme)

        // Draw encoding format indicator at the top
        drawFormatIndicator(context: context, size: size, format: result.encodingFormat)

        return true
    }

    /// Selects the appropriate theme based on encoding format
    /// - Parameter format: The encoding format
    /// - Returns: The theme to use for rendering
    private func selectTheme(for format: PGPFileAnalyzer.EncodingFormat) -> ThumbnailTheme {
        switch format {
        case .binary:
            return .binary
        case .asciiArmored:
            return .asciiArmored
        case .unknown:
            return .binary // Default to binary theme
        }
    }

    /// Draws the background gradient
    /// - Parameters:
    ///   - context: The graphics context
    ///   - size: The thumbnail size
    ///   - theme: The theme to use
    private func drawBackground(context: CGContext, size: CGSize, theme: ThumbnailTheme) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = theme.gradientColors as CFArray

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: size.height),
                                      end: CGPoint(x: 0, y: 0),
                                      options: [])
        }
    }

    /// Draws the lock icon
    /// - Parameters:
    ///   - context: The graphics context
    ///   - size: The thumbnail size
    ///   - theme: The theme to use
    private func drawLockIcon(context: CGContext, size: CGSize, theme: ThumbnailTheme) {
        let lockSize = min(size.width, size.height) * 0.5
        let lockRect = CGRect(
            x: (size.width - lockSize) / 2,
            y: (size.height - lockSize) / 2 + lockSize * 0.15,
            width: lockSize,
            height: lockSize
        )

        if let lockImage = NSImage(systemSymbolName: theme.lockIconName, accessibilityDescription: "Encrypted") {
            // Configure symbol with appropriate size and weight
            let config = NSImage.SymbolConfiguration(pointSize: lockSize * 0.8, weight: .semibold)
            let configuredImage = lockImage.withSymbolConfiguration(config)

            NSGraphicsContext.saveGraphicsState()

            // Set tint color for the lock
            theme.accentColor.set()

            configuredImage?.draw(in: lockRect)

            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Draws the "PGP" badge at the bottom
    /// - Parameters:
    ///   - context: The graphics context
    ///   - size: The thumbnail size
    ///   - theme: The theme to use
    private func drawBadge(context: CGContext, size: CGSize, theme: ThumbnailTheme) {
        let badgeText = "PGP"
        let badgeFont = NSFont.systemFont(ofSize: size.height * 0.12, weight: .bold)
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor.white
        ]

        let badgeString = NSAttributedString(string: badgeText, attributes: badgeAttributes)
        let badgeSize = badgeString.size()

        // Badge background
        let badgePadding: CGFloat = size.height * 0.04
        let badgeRect = CGRect(
            x: (size.width - badgeSize.width - badgePadding * 2) / 2,
            y: size.height * 0.15,
            width: badgeSize.width + badgePadding * 2,
            height: badgeSize.height + badgePadding
        )

        context.saveGState()
        context.setFillColor(theme.badgeColor.cgColor)
        context.addPath(CGPath(roundedRect: badgeRect, cornerWidth: badgeRect.height / 3, cornerHeight: badgeRect.height / 3, transform: nil))
        context.fillPath()
        context.restoreGState()

        // Draw badge text
        let textRect = CGRect(
            x: badgeRect.origin.x + badgePadding,
            y: badgeRect.origin.y + badgePadding / 2,
            width: badgeSize.width,
            height: badgeSize.height
        )
        badgeString.draw(in: textRect)
    }

    /// Draws the encoding format indicator at the top
    /// - Parameters:
    ///   - context: The graphics context
    ///   - size: The thumbnail size
    ///   - format: The encoding format to display
    private func drawFormatIndicator(context: CGContext, size: CGSize, format: PGPFileAnalyzer.EncodingFormat) {
        let formatText = format.description
        let formatFont = NSFont.systemFont(ofSize: size.height * 0.08, weight: .regular)
        let formatAttributes: [NSAttributedString.Key: Any] = [
            .font: formatFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let formatString = NSAttributedString(string: formatText, attributes: formatAttributes)
        let formatSize = formatString.size()
        let formatRect = CGRect(
            x: (size.width - formatSize.width) / 2,
            y: size.height - formatSize.height - size.height * 0.08,
            width: formatSize.width,
            height: formatSize.height
        )
        formatString.draw(in: formatRect)
    }
}
