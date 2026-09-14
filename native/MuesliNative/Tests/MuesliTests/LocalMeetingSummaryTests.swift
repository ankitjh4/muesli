import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Local meeting summary input")
struct LocalMeetingSummaryTests {
    @Test func chunksPreserveEveryCharacterAndBoundUTF8() throws {
        let text = String(repeating: "Maya said नमस्ते 👩🏽‍💻.\n", count: 250)
        let chunks = try LocalSummaryChunks.split(text, maximumBytes: 100)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf8.count <= 100 })
        #expect(try LocalSummaryChunks.split("").isEmpty)
    }

    @Test func rejectsImpossibleLimits() {
        #expect(throws: LocalSummaryChunks.ChunkError.self) { try LocalSummaryChunks.split("abc", maximumBytes: 0) }
        #expect(throws: LocalSummaryChunks.ChunkError.self) { try LocalSummaryChunks.split("👩🏽‍💻", maximumBytes: 1) }
    }

    @Test func prefersWordBoundariesAndKeepsShortSourcesTogether() throws {
        let text = "Maya will send the report on Monday."
        let chunks = try LocalSummaryChunks.split(text, maximumBytes: 15)
        #expect(chunks.joined() == text)
        #expect(chunks.dropLast().allSatisfy { $0.last?.isWhitespace == true })
        let prompts = try LocalMeetingSummary.prompts(sources: [
            .init(label: "Transcript", text: "Maya will send the report."),
            .init(label: "Written notes", text: "Confirm invoice INV-42.")
        ])
        #expect(prompts.count == 1)
        #expect(prompts[0].contains("Source: Written notes"))
    }

    @Test func everyChunkRetainsItsSourceLabel() throws {
        let prompts = try LocalMeetingSummary.prompts(sources: [
            .init(label: "Current transcript", text: String(repeating: "a", count: 4_001)),
            .init(label: "Previous meeting", text: "Old action"),
            .init(label: "Empty", text: "")
        ])
        #expect(prompts.count == 4)
        #expect(prompts.prefix(3).allSatisfy { $0.hasPrefix("Source: Current transcript.") })
        #expect(prompts.last?.hasPrefix("Source: Previous meeting.") == true)
    }
}

@Suite("Local meeting summary model", .enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_LOCAL_SUMMARY"] == "1"))
struct LocalMeetingSummaryModelTests {
    @Test func generatesOfflineAndPreservesWrittenNotes() async throws {
        guard #available(macOS 15, *) else { return }
        var config = AppConfig()
        config.offlineInference = true
        config.meetingSummaryBackend = "openrouter" // Must be ignored offline.
        let result = try await MeetingSummaryClient.summarize(
            transcript: "Maya will send the report on Monday. The budget is 500 rupees. No other decisions were made.",
            meetingTitle: "Project check-in", config: config,
            manualNotesToRetain: "Confirm the invoice number: INV-42."
        )
        print("Local meeting summary: \(result)")
        #expect(result.contains("Maya"))
        #expect(result.contains("500"))
        #expect(result.contains("Monday"))
        #expect(result.contains("Confirm the invoice number: INV-42."))
        #expect(!result.lowercased().contains("morning"))
        #expect(!result.lowercased().contains("under revision"))
        #expect(!result.lowercased().contains("finalization"))
    }
}
