import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Profession vocabulary onboarding")
struct ProfessionVocabularyTests {
    @Test func hostedUsesSelectedModelAndSharedValidation() async throws {
        let config = AppConfig()
        let originalWords = config.customWords
        let words = try await HostedProfessionVocabulary.suggest("  Swift developer  ", excluding: ["Swift"], model: " provider/chosen ", config: config) { system, input, model, _ in
            #expect(system == ProfessionVocabulary.systemPrompt)
            #expect(input == "Swift developer")
            #expect(model == "provider/chosen")
            return #"["Swift", "PostgreSQL", "postgresql", "person@example.com"]"#
        }
        #expect(words == ["PostgreSQL"])
        #expect(config.customWords == originalWords)
    }

    @Test func hostedRejectsOfflineBeforeGeneration() async {
        var config = AppConfig()
        config.offlineInference = true
        do {
            _ = try await HostedProfessionVocabulary.suggest("Developer", excluding: [], model: "provider/model", config: config) { _, _, _, _ in
                Issue.record("Offline vocabulary must not invoke hosted generation")
                return "[]"
            }
            Issue.record("Expected offline rejection")
        } catch { #expect(error is TranscriptCleanupError) }
    }

    @Test func hostedRequiresExplicitModelAndValidDescription() async {
        for (description, model) in [("Developer", " "), (" ", "provider/model"), (String(repeating: "x", count: 2001), "provider/model")] {
            do {
                _ = try await HostedProfessionVocabulary.suggest(description, excluding: [], model: model, config: AppConfig()) { _, _, _, _ in
                    Issue.record("Invalid input must not invoke generation")
                    return "[]"
                }
                Issue.record("Expected input rejection")
            } catch { #expect(error is TranscriptCleanupError) }
        }
    }

    @Test func validatesDeduplicatesAndExcludesKnownWords() throws {
        let output = #"["Swift", "swift", "C++", "PostgreSQL", "भारत", "https://example.com", "person@example.com", "42", "A sentence containing far too many words to be vocabulary"]"#
        #expect(try ProfessionVocabulary.parse(output, excluding: ["postgresql"]) == ["Swift", "C++", "भारत"])
    }

    @Test func rejectsCommentaryAndObjects() {
        #expect(throws: ProfessionVocabulary.ValidationError.self) {
            try ProfessionVocabulary.parse("Here are some words: [\"Swift\"]")
        }
        #expect(throws: ProfessionVocabulary.ValidationError.self) {
            try ProfessionVocabulary.parse("{\"words\":[\"Swift\"]}")
        }
    }

    @Test func descriptionPersistsWithoutAddingUnapprovedWords() throws {
        var config = AppConfig()
        config.professionDescription = "I build apps in Swift."
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(restored.professionDescription == config.professionDescription)
        #expect(restored.customWords == config.customWords)
    }
}

@Suite("Local profession vocabulary model", .enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_VOCABULARY_MODEL"] == "1"))
struct ProfessionVocabularyModelTests {
    @Test func generatesReviewableTermsLocally() async throws {
        guard #available(macOS 15, *) else { return }
        let coordinator = TranscriptionCoordinator()
        do {
            let words = try await coordinator.suggestProfessionVocabulary(
                "I am a software developer. I build macOS apps in Swift and use PostgreSQL and Kubernetes.",
                excluding: []
            )
            print("Local profession vocabulary: \(words)")
            #expect(!words.isEmpty)
            #expect(words.count <= 40)
            #expect(words.contains { ["swift", "postgresql", "kubernetes"].contains($0.lowercased()) })
            await coordinator.shutdown()
        } catch {
            await coordinator.shutdown()
            throw error
        }
    }
}
