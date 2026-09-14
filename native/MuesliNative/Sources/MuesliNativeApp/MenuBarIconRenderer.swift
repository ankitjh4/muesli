import AppKit

enum MenuBarIconRenderer {

    struct Option: Equatable {
        let id: String
        let label: String
    }

    private static let displaySize = NSSize(width: 18, height: 18)
    private static let emojiPrefix = "emoji:"
    /// Pixel bounds of the blue waveform inside the canonical 1024px app icon.
    /// The menu-bar mark is extracted from this source directly; it is never
    /// reconstructed from approximate bars or inferred measurements.
    static let canonicalMarkSourceRect = CGRect(x: 195, y: 256, width: 635, height: 513)
    static let canonicalMarkOpacityBoost: CGFloat = 1.08
    static let canonicalMarkMask: CGImage? = loadCanonicalMarkMask()

    /// Built-in identity choices for the menu bar, sidebar, and idle indicator.
    /// Emoji choices use the same persisted string as SF Symbols, so older
    /// configurations remain compatible and custom emoji require no migration.
    static let options: [Option] = [
        Option(id: "muesli", label: "Muesli+ Logo"),
        Option(id: "mic.fill", label: "Microphone"),
        Option(id: "waveform", label: "Waveform"),
        Option(id: "bubble.left.fill", label: "Bubble"),
        Option(id: "text.bubble", label: "Speech Bubble"),
        Option(id: "pencil.line", label: "Pencil"),
        Option(id: "brain.head.profile", label: "Brain"),
        Option(id: "sparkles", label: "Sparkles"),
        Option(id: "headphones", label: "Headphones"),
        Option(id: "person.wave.2", label: "Meeting"),
        Option(id: "character.bubble", label: "Character"),
        Option(id: "doc.text", label: "Document"),
        Option(id: "bird.fill", label: "Bird"),
        Option(id: "cat.fill", label: "Cat"),
        Option(id: "dog.fill", label: "Dog"),
        Option(id: "hare.fill", label: "Hare"),
        Option(id: "tortoise.fill", label: "Tortoise"),
        Option(id: "fish.fill", label: "Fish"),
        Option(id: "ant.fill", label: "Ant"),
        Option(id: "ladybug.fill", label: "Ladybug"),
        Option(id: "pawprint.fill", label: "Paw"),
        Option(id: "emoji:🐐", label: "Goat"),
        Option(id: "emoji:🦊", label: "Fox"),
        Option(id: "emoji:🦉", label: "Owl"),
        Option(id: "emoji:🐼", label: "Panda"),
        Option(id: "emoji:🐸", label: "Frog"),
        Option(id: "emoji:🐙", label: "Octopus"),
        Option(id: "emoji:🦋", label: "Butterfly"),
        Option(id: "emoji:🐝", label: "Bee"),
        Option(id: "emoji:🦁", label: "Lion"),
        Option(id: "emoji:🐯", label: "Tiger"),
        Option(id: "emoji:🐨", label: "Koala"),
        Option(id: "emoji:🐧", label: "Penguin"),
        Option(id: "emoji:🦄", label: "Unicorn"),
    ]

    /// Returns the configured menu bar/floating indicator icon. The Muesli+ mark
    /// is drawn as a resolution-independent template so its narrow waveform
    /// gaps stay crisp at menu-bar scale.
    static func make(choice: String = "muesli") -> NSImage? {
        if choice == "muesli" {
            return makeMuesliMark()
        }
        if let emoji = emoji(from: choice) {
            return makeEmoji(emoji)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let description = options.first(where: { $0.id == choice })?.label ?? "Muesli+"
        let image = NSImage(systemSymbolName: choice, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    static func emoji(from choice: String) -> String? {
        guard choice.hasPrefix(emojiPrefix) else { return nil }
        let emoji = String(choice.dropFirst(emojiPrefix.count))
        return normalizedEmoji(emoji)
    }

    static func choice(forEmoji input: String) -> String? {
        normalizedEmoji(input).map { emojiPrefix + $0 }
    }

    static func isEmojiChoice(_ choice: String) -> Bool {
        emoji(from: choice) != nil
    }

    static func compactWordCount(_ count: Int) -> String {
        let clampedCount = max(count, 0)
        let units: [(threshold: Int, suffix: String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "b"),
            (1_000_000, "m"),
            (1_000, "k"),
        ]
        for unit in units where clampedCount >= unit.threshold {
            return "\(clampedCount / unit.threshold)\(unit.suffix)"
        }
        return "\(clampedCount)"
    }

    static func hotkeyCueLabel(for hotkey: HotkeyConfig) -> String {
        if hotkey.isCombination {
            return hotkey.label
        }
        switch hotkey.keyCode {
        case 55: return "L⌘"
        case 54: return "R⌘"
        case 63: return "fn"
        case 59: return "L⌃"
        case 62: return "R⌃"
        case 58: return "L⌥"
        case 61: return "R⌥"
        case 56: return "L⇧"
        case 60: return "R⇧"
        default: return hotkey.displayLabel
        }
    }

    static func statusTitle(
        hotkey: HotkeyConfig,
        showsHotkey: Bool = true,
        wordCount: Int? = nil,
        detail: String? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let wordCount {
            result.append(NSAttributedString(
                string: "\u{2009}\(compactWordCount(wordCount))",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .baselineOffset: 0,
                ]
            ))
        }

        if showsHotkey {
            if result.length > 0 {
                result.append(NSAttributedString(string: "  "))
            }
            result.append(NSAttributedString(
                string: wordCount == nil
                    ? "\u{2009}\(hotkeyCueLabel(for: hotkey))"
                    : hotkeyCueLabel(for: hotkey),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                    .baselineOffset: 1,
                ]
            ))
        }
        if let detail, !detail.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(string: "  "))
            }
            result.append(NSAttributedString(
                string: detail,
                attributes: [.font: NSFont.menuBarFont(ofSize: 0)]
            ))
        }
        return result
    }

    private static func makeMuesliMark() -> NSImage {
        guard let canonicalMarkMask else {
            return makeBundledMarkFallback()
        }

        let sourceSize = NSSize(
            width: canonicalMarkMask.width,
            height: canonicalMarkMask.height
        )
        let sourceImage = NSImage(cgImage: canonicalMarkMask, size: sourceSize)
        let image = NSImage(size: displaySize, flipped: false) { rect in
            let markHeight: CGFloat = 14
            let markWidth = markHeight * sourceSize.width / sourceSize.height
            let markRect = NSRect(
                x: rect.midX - markWidth / 2,
                y: rect.midY - markHeight / 2,
                width: markWidth,
                height: markHeight
            )
            sourceImage.draw(
                in: markRect,
                from: NSRect(origin: .zero, size: sourceSize),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )

            return true
        }
        image.isTemplate = true
        return image
    }

    private static func normalizedEmoji(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first else { return nil }
        let containsEmoji = character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation ||
                scalar.value == 0xFE0F
        }
        return containsEmoji ? trimmed : nil
    }

    private static func makeEmoji(_ emoji: String) -> NSImage {
        let image = NSImage(size: displaySize, flipped: false) { rect in
            let font = NSFont(name: "Apple Color Emoji", size: 15)
                ?? NSFont.systemFont(ofSize: 15)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let emojiString = emoji as NSString
            let emojiSize = emojiString.size(withAttributes: attributes)
            let origin = NSPoint(
                x: rect.midX - emojiSize.width / 2,
                y: rect.midY - emojiSize.height / 2
            )
            emojiString.draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func loadCanonicalMarkMask() -> CGImage? {
        guard let sourceURL = canonicalAppIconURL(),
              let sourceImage = NSImage(contentsOf: sourceURL),
              let sourceCGImage = sourceImage.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
              ),
              let croppedImage = sourceCGImage.cropping(to: canonicalMarkSourceRect) else {
            return nil
        }

        let width = croppedImage.width
        let height = croppedImage.height
        let bytesPerRow = width * 4
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue

        guard let inputContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ), let inputData = inputContext.data else {
            return nil
        }

        inputContext.interpolationQuality = .none
        inputContext.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let inputPixels = inputData.assumingMemoryBound(to: UInt8.self)
        let pixelCount = width * height
        var backgroundBlue = 255
        var foregroundBlue = 0
        for pixel in 0..<pixelCount {
            let blue = Int(inputPixels[pixel * 4 + 2])
            backgroundBlue = min(backgroundBlue, blue)
            foregroundBlue = max(foregroundBlue, blue)
        }
        guard foregroundBlue > backgroundBlue else { return nil }

        guard let outputContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ), let outputData = outputContext.data else {
            return nil
        }

        let outputPixels = outputData.assumingMemoryBound(to: UInt8.self)
        let blueRange = foregroundBlue - backgroundBlue
        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            let sourceBlue = Int(inputPixels[offset + 2])
            let sourceAlpha = max(0, min(255, (sourceBlue - backgroundBlue) * 255 / blueRange))
            let alpha = min(255, Int((CGFloat(sourceAlpha) * canonicalMarkOpacityBoost).rounded()))
            outputPixels[offset] = 0
            outputPixels[offset + 1] = 0
            outputPixels[offset + 2] = 0
            outputPixels[offset + 3] = UInt8(alpha)
        }

        return outputContext.makeImage()
    }

    private static func canonicalAppIconURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "muesli_app_icon", withExtension: "png") {
            return bundled
        }

        let fileManager = FileManager.default
        let startingPoints = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
        ]
        for startingPoint in startingPoints {
            var directory = startingPoint
            for _ in 0..<8 {
                let candidate = directory.appendingPathComponent("assets/muesli_app_icon.png")
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
                directory.deleteLastPathComponent()
            }
        }
        return nil
    }

    private static func makeBundledMarkFallback() -> NSImage {
        if let url = Bundle.main.url(forResource: "menu_m_template", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = displaySize
            image.isTemplate = true
            return image
        }

        let image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Muesli+"
        ) ?? NSImage(size: displaySize)
        image.size = displaySize
        image.isTemplate = true
        return image
    }

}
