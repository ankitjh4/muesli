import Testing
import MuesliCore

@Suite("Frequent vocabulary learning")
struct FrequentVocabularyTests {
    @Test func countsSeparateDictationsNotRepeatedWords() {
        let result = FrequentVocabulary.candidates(
            transcripts: ["Kubernetes Kubernetes Kubernetes", "Review Kubernetes", "Deploy Kubernetes"],
            excluding: []
        )
        #expect(result.map(\.word) == ["Kubernetes"])
        #expect(result.first?.dictationCount == 3)
        #expect(FrequentVocabulary.candidates(transcripts: ["Kubernetes Kubernetes Kubernetes"], excluding: []).isEmpty)
    }

    @Test func excludesKnownAndCommonWords() {
        let text = "please review Kubernetes tomorrow"
        let result = FrequentVocabulary.candidates(transcripts: [text, text, text], excluding: ["kubernetes", "review"])
        #expect(result.isEmpty)
    }

    @Test func preservesIndicWordsAndStableOrdering() {
        let result = FrequentVocabulary.candidates(transcripts: Array(repeating: "भारत Zoom GitHub", count: 3), excluding: [])
        #expect(Set(result.map(\.word)) == Set(["भारत", "Zoom", "GitHub"]))
        #expect(result.map(\.id) == result.map(\.id).sorted())
        #expect(FrequentVocabulary.candidates(transcripts: [], excluding: [], limit: -1).isEmpty)
    }

    @Test func confirmedVocabularyUsesExistingCorrectionPipeline() throws {
        let candidates = FrequentVocabulary.candidates(
            transcripts: Array(repeating: "Deploy Kubernetes", count: 3), excluding: ["deploy"]
        )
        let word = try #require(candidates.first?.word)
        let dictionary = [CustomWord(word: word, replacement: word)]
        #expect(CustomWordMatcher.apply(text: "Deploy Kubernetez today.", customWords: dictionary) == "Deploy Kubernetes today.")
    }
}
