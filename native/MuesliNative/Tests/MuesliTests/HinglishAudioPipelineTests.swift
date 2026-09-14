import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

/// Run alone with MUESLI_TEST_HINGLISH_WAV pointing to a synthetic or explicitly
/// supplied recording. Requires the downloaded Bodhan Flex INT8 and Qwen 0.8B.
@Suite("Hinglish audio pipeline", .enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_HINGLISH_WAV"] != nil))
struct HinglishAudioPipelineTests {
    @Test func localAudioThroughSpeechAndRomanization() async throws {
        guard #available(macOS 15, *) else { return }
        let path = try #require(ProcessInfo.processInfo.environment["MUESLI_TEST_HINGLISH_WAV"])
        let url = URL(fileURLWithPath: path)
        #expect(BackendOption.bodhanFlexInt8.isDownloaded)
        #expect(PostProcessorOption.qwen35_0_8b.isDownloaded)
        ModelNetworkPolicy.shared.setAllowed(false)
        defer { ModelNetworkPolicy.shared.setAllowed(true) }
        let coordinator = TranscriptionCoordinator()
        var config = AppConfig()
        config.offlineInference = true
        config.romanizeHindi = false
        await coordinator.configurePostProcessor(backend: .local, option: .qwen35_0_8b,
            systemPrompt: PostProcessorOption.defaultSystemPrompt, config: config)
        let raw = try await coordinator.transcribeDictation(at: url, backend: .bodhanFlexInt8)
        print("Hinglish ASR: \(raw.text)")
        #expect(raw.text.range(of: "[\\u0900-\\u097F]", options: .regularExpression) != nil)
        config.romanizeHindi = true
        await coordinator.configurePostProcessor(backend: .local, option: .qwen35_0_8b,
            systemPrompt: PostProcessorOption.defaultSystemPrompt, config: config)
        let final = try await coordinator.transcribeDictation(at: url, backend: .bodhanFlexInt8)
        print("Hinglish final: \(final.text)")
        #expect(!final.text.isEmpty)
        #expect(final.text.range(of: "[\\u0900-\\u097F]", options: .regularExpression) == nil)
        #expect(final.text.lowercased().contains("report"))
        #expect(final.text.lowercased().contains("baje hai"))
        await coordinator.shutdown()
    }
}
