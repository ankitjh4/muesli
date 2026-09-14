import AppKit
import SwiftUI
import Testing
@testable import MuesliNativeApp

@Suite("Home dashboard", .serialized)
@MainActor
struct HomeDashboardTests {
    @Test func pipelineExplainsMixedModeAndDoesNotClaimRomanizationForHostedSpeech() {
        var config = AppConfig()
        config.dictationProvider = DictationProvider.openRouter.rawValue
        config.openRouterDictationModel = "example/speech"
        config.enablePostProcessor = true
        config.romanizeHindi = true
        let pipeline = HomePipelineSummary(config: config, backend: .bodhanFlexInt8)
        #expect(pipeline.speech == "example/speech")
        #expect(pipeline.speechLocation == "Audio sent to OpenRouter")
        #expect(!pipeline.output.contains("Roman"))
    }

    @Test func localBodhanExplainsSecondLanguageModelStage() {
        var config = AppConfig()
        config.dictationProvider = DictationProvider.local.rawValue
        config.romanizeHindi = true
        config.enablePostProcessor = false
        let pipeline = HomePipelineSummary(config: config, backend: .bodhanFlexInt8)
        #expect(pipeline.output.contains("Hindi → Roman letters"))
        #expect(pipeline.cleanup == "Original transcript")
    }

    @Test func defaultLandingPageIsHomeAndAppearanceIsLight() {
        #expect(AppState().selectedTab == .home)
        #expect(!AppConfig().darkMode)
    }

    @Test func renderReviewSnapshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["MUESLI_UI_SNAPSHOT_DIR"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, width, height, dark) in [
            ("home-light", 840.0, 1220.0, false),
            ("home-dark", 840.0, 1220.0, true),
            ("home-narrow", 280.0, 900.0, false),
        ] {
            var config = AppConfig()
            config.userName = "Ankit"
            config.enablePostProcessor = true
            config.activePostProcessorId = PostProcessorOption.qwen35_0_8b.id
            config.romanizeHindi = true
            let content = HomeDashboardContent(
                name: config.userName, hotkey: config.dictationHotkey.label,
                offline: false, quillEnabled: true,
                pipeline: HomePipelineSummary(config: config, backend: .bodhanFlexInt8),
                onModels: {}, onHistory: {}, onMeetings: {}, onQuill: {}, onDictionary: {}, onShortcuts: {}
            )
            let host = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("\(name).png"))
            #expect(bitmap.pixelsWide >= Int(width))
            window.contentView = nil
        }
    }
}
