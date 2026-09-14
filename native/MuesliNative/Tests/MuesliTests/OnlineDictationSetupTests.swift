import AppKit
import SwiftUI
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Online dictation setup")
struct OnlineDictationSetupTests {
    @Test func meetingResumeReadinessFollowsSelectedRoute() {
        var config = AppConfig()
        config.useOpenRouterForMeetings = true
        config.openRouterMeetingModel = "provider/speech"
        let ready = OnlineDictationSetupPolicy.isMeetingReady(config: config, authenticated: true, localModelReady: false)
        #expect(ready)
        #expect(OnboardingFlow.setupGatedResumeStep(requestedStep: OnboardingFlow.Step.quill.rawValue,
            setupStep: .meetingTranscription, isReady: ready) == OnboardingFlow.Step.quill.rawValue)
        #expect(!OnlineDictationSetupPolicy.isMeetingReady(config: config, authenticated: false, localModelReady: true))
        config.openRouterMeetingModel = " "
        #expect(!OnlineDictationSetupPolicy.isMeetingReady(config: config, authenticated: true, localModelReady: true))
        config.offlineInference = true
        #expect(!OnlineDictationSetupPolicy.isMeetingReady(config: config, authenticated: true, localModelReady: false))
        #expect(OnlineDictationSetupPolicy.isMeetingReady(config: config, authenticated: false, localModelReady: true))
    }

    @Test func quillKeepsExplicitHostedChoiceWithoutInventingOne() {
        var config = AppConfig()
        #expect(OnboardingQuillModelSelection.openRouterModel(in: config).isEmpty)
        #expect(OnboardingQuillModelSelection.completedModel(backend: .hosted(.openRouter), config: config).isEmpty)
        config.quilBackend = TranscriptCleanupBackendOption.hosted(.openRouter).backend
        config.quilModel = "  provider/chosen-text-model  "
        #expect(OnboardingQuillModelSelection.completedModel(backend: .hosted(.openRouter), config: config) == "provider/chosen-text-model")
        #expect(OnboardingQuillModelSelection.completedModel(backend: .local, config: config) == PostProcessorOption.defaultQuilOption.id)
        config.quilModel = " \n "
        #expect(OnboardingQuillModelSelection.completedModel(backend: .hosted(.openRouter), config: config).isEmpty)
    }

    @Test @MainActor func renderBuildingBlocks() async throws {
        guard let path = ProcessInfo.processInfo.environment["MUESLI_UI_SNAPSHOT_DIR"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: OnboardingView.ConceptsView().background(MuesliTheme.backgroundBase).environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("onboarding-building-blocks.png"))
    }

    @Test func requiresCredentialAndExplicitModelButNoLocalDownload() {
        #expect(!OnlineDictationSetupPolicy.isReady(authenticated: false, modelID: "provider/speech"))
        #expect(!OnlineDictationSetupPolicy.isReady(authenticated: true, modelID: " \n "))
        #expect(OnlineDictationSetupPolicy.isReady(authenticated: true, modelID: "provider/speech"))
    }

    @Test @MainActor func renderOnlineOnboarding() async throws {
        guard let path = ProcessInfo.processInfo.environment["MUESLI_UI_SNAPSHOT_DIR"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-online-render-\(UUID().uuidString)")
        let store = DictationStore(databaseURL: support.appendingPathComponent("muesli.db"))
        try store.migrateIfNeeded()
        let controller = MuesliController(
            runtime: RuntimePaths(repoRoot: FileManager.default.temporaryDirectory, menuIcon: nil, appIcon: nil, bundlePath: nil),
            dictationStore: store, configStore: ConfigStore(supportDirectory: support)
        )
        controller.appState.config.dictationProvider = DictationProvider.openRouter.rawValue
        controller.appState.isOpenRouterAuthenticated = false
        // Render the pure setup card, not OnboardingView: the full flow persists
        // progress to the running app identity and must not run in a snapshot test.
        let host = NSHostingView(rootView: OnlineDictationSetupView(controller: controller, appState: controller.appState).padding(32).environment(\.colorScheme, .light))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 480)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("onboarding-online-card.png"))
        window.contentView = nil

        let meetingHost = NSHostingView(rootView: OnlineDictationSetupView(
            controller: controller, appState: controller.appState, forMeetings: true
        ).padding(24).environment(\.colorScheme, .light))
        meetingHost.sizingOptions = []
        meetingHost.frame = NSRect(x: 0, y: 0, width: 600, height: 620)
        let meetingWindow = NSWindow(contentRect: meetingHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        meetingWindow.appearance = NSAppearance(named: .aqua)
        meetingWindow.contentView = meetingHost
        meetingHost.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        meetingHost.layoutSubtreeIfNeeded()
        let meetingBitmap = try #require(meetingHost.bitmapImageRepForCachingDisplay(in: meetingHost.bounds))
        #expect(meetingHost.bounds.height == 620)
        meetingHost.cacheDisplay(in: meetingHost.bounds, to: meetingBitmap)
        let meetingPNG = try #require(meetingBitmap.representation(using: .png, properties: [:]))
        try meetingPNG.write(to: output.appendingPathComponent("onboarding-online-meeting-card.png"))
        meetingWindow.contentView = nil

        // A populated mock catalog avoids real network work in this rendering check.
        controller.appState.openRouterSummaryModels = [SummaryModelPreset(id: "test/text-model", label: "Example text model")]
        controller.appState.openRouterSummaryCatalogState = .loaded
        let textHost = NSHostingView(rootView: OpenRouterTextModelSetupView(
            controller: controller, appState: controller.appState, modelID: .constant("test/text-model")
        ).padding(24).background(MuesliTheme.backgroundBase).environment(\.colorScheme, .light))
        textHost.frame = NSRect(x: 0, y: 0, width: 600, height: 240)
        let textWindow = NSWindow(contentRect: textHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        textWindow.appearance = NSAppearance(named: .aqua)
        textWindow.contentView = textHost
        defer { textWindow.contentView = nil }
        textHost.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        textHost.layoutSubtreeIfNeeded()
        let textBitmap = try #require(textHost.bitmapImageRepForCachingDisplay(in: textHost.bounds))
        textHost.cacheDisplay(in: textHost.bounds, to: textBitmap)
        let textPNG = try #require(textBitmap.representation(using: .png, properties: [:]))
        try textPNG.write(to: output.appendingPathComponent("onboarding-text-model.png"))
    }
}
