import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

/// Opt-in quality smoke test: requires the downloaded GGUF and runs real local
/// inference. Unit tests with canned generations cannot establish model quality.
@Suite("Local Hindi romanization model", .enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_ROMANIZATION_MODEL"] == "1"))
struct HindiRomanizationModelTests {
    @Test func mixedLanguageQualitySmoke() async throws {
        guard #available(macOS 15, *) else { return }
        let option = PostProcessorOption.qwen35_0_8b
        #expect(option.isDownloaded)
        let processor = Qwen3PostProcessor(
            modelURL: option.modelURL, systemPrompt: HindiRomanization.systemPrompt,
            inputFormat: .configurable
        )
        let configuration = Qwen3PostProcessor.Configuration(
            modelURL: option.modelURL, systemPrompt: HindiRomanization.systemPrompt,
            inputFormat: .configurable,
            sampling: ProcessInfo.processInfo.environment["MUESLI_TEST_ROMANIZATION_SAMPLED"] == "1" ? .vocabulary : .deterministic
        )
        let cases: [(String, Set<String>)] = [
            ("नमस्ते", ["namaste"]),
            ("आज", ["aaj", "aj"]),
            ("काम", ["kaam", "kam"]),
            ("भेजो", ["bhejo"]),
            ("भारत", ["bharat", "bhaarat"]),
            ("धन्यवाद", ["dhanyavaad", "dhanyavad", "dhanyawaad", "dhanyawad"]),
            ("खाना", ["khana", "khaana"]),
            ("किताब", ["kitab", "kitaab"]),
            ("है", ["hai"]),
            ("हैं", ["hain"]),
            ("मैं", ["main"]),
            ("में", ["mein", "men"]),
        ]
        for (input, accepted) in cases {
            let output = try await processor.romanizeHindi(input, configuration: configuration)
            print("Romanization quality: \(input) -> \(output)")
            #expect(accepted.contains(output.lowercased()))
        }
        let output = try await processor.romanizeHindi("Send नमस्ते on Zoom at 5:30, ₹५००.", configuration: configuration)
        print("Mixed romanization quality: \(output)")
        #expect(output.lowercased() == "send namaste on zoom at 5:30, ₹५००.")
        await processor.shutdown()
    }
}
