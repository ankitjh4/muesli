import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Cleanup defaults and model discovery")
struct CleanupDefaultsTests {
    @Test("Existing stock prompt migrates to meaning-preserving cleanup")
    func stockPromptMigration() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "post_processor_system_prompt": PostProcessorOption.legacySystemPrompt,
            "active_transcript_cleanup_prompt_id": TranscriptCleanupPrompts.defaultID,
        ])
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.postProcessorSystemPrompt == PostProcessorOption.defaultSystemPrompt)
    }

    @Test("A user's edited prompt is preserved")
    func customPromptPreserved() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "post_processor_system_prompt": "Keep my custom formatting.",
        ])
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.postProcessorSystemPrompt == "Keep my custom formatting.")
    }

    @Test("Text catalog includes paid and short-context models, excludes audio-only")
    func textCatalog() throws {
        let json = """
        {"data":[
          {"id":"paid/small","name":"Small paid","context_length":8192,"pricing":{"prompt":"0.001","completion":"0.002"},"architecture":{"output_modalities":["text"]}},
          {"id":"audio/only","name":"Audio","pricing":{},"architecture":{"output_modalities":["transcription"]}}
        ]}
        """
        let catalog = try JSONDecoder().decode(OpenRouterModelCatalog.self, from: Data(json.utf8))
        #expect(OpenRouterModelCatalogFilter.textGenerationPresets(from: catalog.data).map(\.id) == ["paid/small"])
    }
}
