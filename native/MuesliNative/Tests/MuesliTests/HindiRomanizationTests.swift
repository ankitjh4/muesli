import Testing
import MuesliCore

@Suite("Hindi romanization preserves mixed dictation")
struct HindiRomanizationTests {
    @Test func mechanicalDraftPreservesWrittenVowelsAndAspirates() {
        #expect(HindiRomanization.modelInput(for: "खाना").contains("Mechanical Latin draft: khana"))
        #expect(HindiRomanization.modelInput(for: "भेजो").contains("Mechanical Latin draft: bhejo"))
        #expect(HindiRomanization.modelInput(for: "काम").contains("Mechanical Latin draft: kam"))
    }

    @Test func preservesEnglishNumbersAndPunctuation() async throws {
        let original = "Send राहुल ₹५०० at 5:30; Zoom link भेजो."
        let result = try await HindiRomanization.romanize(original) { word in
            switch word {
            case "राहुल": return "Rahul"
            case "भेजो": return "bhejo"
            default: Issue.record("Unexpected model input: \(word)"); return ""
            }
        }
        #expect(result == "Send Rahul ₹५०० at 5:30; Zoom link bhejo.")
    }

    @Test func englishDoesNotInvokeModel() async throws {
        let result = try await HindiRomanization.romanize("Open GitHub issue #42") { _ in
            Issue.record("English-only transcription must bypass the model")
            return ""
        }
        #expect(result == "Open GitHub issue #42")
    }

    @Test func rejectsMissingAndUnconvertedText() {
        #expect(HindiRomanization.acceptedReplacement("", for: "नमस्ते") == nil)
        #expect(HindiRomanization.acceptedReplacement("नमस्ते", for: "नमस्ते") == nil)
        #expect(HindiRomanization.acceptedReplacement("Here is the answer you requested", for: "नमस्ते") == nil)
        #expect(HindiRomanization.acceptedReplacement("namaste", for: "नमस्ते") == "namaste")
    }

    @Test func invalidGenerationFailsInsteadOfReturningPartialTranscript() async {
        do {
            _ = try await HindiRomanization.romanize("आज meeting है") { word in
                word == "आज" ? "aaj" : ""
            }
            Issue.record("Invalid output must fail the complete romanization stage")
        } catch HindiRomanization.RomanizationError.invalidOutput {
            // The runtime can retain the entire original transcript.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func inferenceFailureIsNotSilentlySwallowed() async {
        struct InferenceFailure: Error {}
        do {
            _ = try await HindiRomanization.romanize("Send नमस्ते") { _ in
                throw InferenceFailure()
            }
            Issue.record("Expected inference error")
        } catch is InferenceFailure {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
