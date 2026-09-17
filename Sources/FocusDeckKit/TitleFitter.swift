import Foundation
import CoreGraphics

/// Work out a big, readable font size for the focus title inside a given box.
public enum TitleFitter {

    /// Average glyph width as a fraction of the font size for a heavy sans font.
    public static let averageGlyphRatio: CGFloat = 0.60
    /// Line height as a fraction of the font size.
    public static let lineHeightRatio: CGFloat = 1.18

    /// Smallest size we accept before letting the text shrink itself.
    public static let absoluteFloor: CGFloat = 36
    /// Largest size we ever use, however wide the window is.
    public static let absoluteCeiling: CGFloat = 200

    /// Target size for this window width: clamp(0.10 * width, 70, 200).
    public static func targetSize(forWidth width: CGFloat) -> CGFloat {
        min(absoluteCeiling, max(70, width * 0.10))
    }

    /// Do-not-go-below size: clamp(0.052 * width, 36, 80).
    public static func floorSize(forWidth width: CGFloat) -> CGFloat {
        min(80, max(absoluteFloor, width * 0.052))
    }

    /// Largest font size where `text` still fits in `size`.
    /// The result is capped by the window-width target and lifted to the floor size.
    /// - Parameters:
    ///   - maxLines: how many lines the text may use.
    ///   - padding: horizontal padding already reserved by the caller (points).
    public static func fontSize(for text: String, in size: CGSize, scale: CGFloat = 1,
                                maxLines: Int = 3, padding: CGFloat = 48) -> CGFloat {
        let fitted = rawFit(for: text, in: size, maxLines: maxLines, padding: padding)
        let target = targetSize(forWidth: size.width)
        // The floor is a readability preference, so it may lift a small size only so far:
        // a pasted URL must not be drawn at 60 pt just because the window is wide.
        let floor = min(floorSize(forWidth: size.width), fitted * 2)
        return max(floor, min(fitted, target)) * scale
    }

    /// The largest size that fits the box, before the window-width clamps.
    static func rawFit(for text: String, in size: CGSize, maxLines: Int = 3,
                       padding: CGFloat = 48) -> CGFloat {
        let usableWidth = max(80, size.width - padding)
        let usableHeight = max(60, size.height)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 72 }

        let words = trimmed.split(separator: " ")
        let longestWord = words.map(\.count).max() ?? trimmed.count
        var best: CGFloat = 12

        for lines in 1...max(1, maxLines) {
            // Width is limited by the longest word and by the average line fill.
            let perLine = Double(trimmed.count) / Double(lines)
            let estimatedCharsPerLine = max(Double(longestWord), perLine * 0.92)
            let widthLimit = usableWidth / (CGFloat(estimatedCharsPerLine) * averageGlyphRatio)
            let heightLimit = usableHeight * 0.82 / (CGFloat(lines) * lineHeightRatio)
            best = max(best, min(widthLimit, heightLimit))
        }
        return min(best, usableHeight * 0.9)
    }

    /// Break a title into at most `maxLines` balanced lines (rough word wrap).
    public static func balancedLines(for text: String, maxLines: Int = 4) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var bestLines = words
        var bestScore = Double.greatestFiniteMagnitude

        for lines in 1...max(1, maxLines) {
            guard lines <= words.count || lines == 1 else { continue }
            let target = Double(text.count) / Double(lines)
            var buckets: [[String]] = []
            var current: [String] = []
            var size = 0
            for word in words {
                if !current.isEmpty && Double(size + word.count + 1) > target * 1.18 {
                    buckets.append(current)
                    current = []
                    size = 0
                }
                current.append(word)
                size += word.count + 1
            }
            if !current.isEmpty { buckets.append(current) }
            let lengths = buckets.map { $0.joined(separator: " ").count }
            let spread = Double((lengths.max() ?? 0) - (lengths.min() ?? 0))
            let penalty = spread + Double(abs(buckets.count - lines)) * 40
            if penalty < bestScore {
                bestScore = penalty
                bestLines = buckets.map { $0.joined(separator: " ") }
            }
        }
        return bestLines
    }
}
