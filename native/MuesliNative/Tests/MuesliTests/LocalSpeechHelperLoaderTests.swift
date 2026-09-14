import Foundation
import FluidAudio
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Offline speech helper loading")
struct LocalSpeechHelperLoaderTests {
    /// Run alone: downloads Tiny if needed, then reloads/decodes with the shared
    /// network policy disabled. Input must be synthetic or explicitly supplied.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_WHISPER_WAV"] != nil))
    func realWhisperOfflineDecode() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["MUESLI_TEST_WHISPER_WAV"])
        let url = URL(fileURLWithPath: path)
        #expect(FileManager.default.fileExists(atPath: path))
        let previousPolicy = ModelNetworkPolicy.shared.isAllowed
        defer { ModelNetworkPolicy.shared.setAllowed(previousPolicy) }
        let transcriber = WhisperKitTranscriber()
        do {
            ModelNetworkPolicy.shared.setAllowed(true)
            try await transcriber.loadModel(modelName: "tiny")
            #expect(ManagedWhisperKit.tokenizerFilesReady(modelName: "tiny"))
            await transcriber.shutdown()
            ModelNetworkPolicy.shared.setAllowed(false)
            try await transcriber.loadModel(modelName: "tiny")
            let result = try await transcriber.transcribe(wavURL: url)
            #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!result.text.contains("<|"))
            print("Whisper Tiny offline synthetic decode: \(result.text)")
            await transcriber.shutdown()
        } catch {
            await transcriber.shutdown()
            throw error
        }
    }

    @Test func everySelectableWhisperHasTokenizerMapping() {
        for backend in BackendOption.all where backend.backend == "whisper" {
            #expect(ManagedWhisperKit.variantForAppModel(backend.model) != nil)
        }
        #expect(ManagedWhisperKit.variantForAppModel("openai_whisper-small.en")?.description == "small.en")
        #expect(ManagedWhisperKit.variantForAppModel("unknown") == nil)
        #expect(ManagedWhisperKit.variantForAppModel(BackendOption.whisperHinglishRomanized.model)?.description == "large-v3")
    }

    @Test func whisperReadinessRequiresBothFilesAndMatchesBundlePriority() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-tokenizer-readiness-\(UUID())")
        let bundle = root.appendingPathComponent("speech")
        let cache = root.appendingPathComponent("cache")
        let plan = ManagedWhisperKit.tokenizerPlan(for: .small, cacheRoot: cache)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plan.cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func ready() -> Bool { ManagedWhisperKit.tokenizerFilesReady(modelName: "small", modelFolder: bundle, cacheRoot: cache) }
        #expect(!ready())
        try Data("{}".utf8).write(to: plan.cacheDirectory.appendingPathComponent("tokenizer.json"))
        #expect(!ready())
        try Data("{}".utf8).write(to: plan.cacheDirectory.appendingPathComponent("tokenizer_config.json"))
        #expect(ready())
        // An incomplete bundled tokenizer shadows the otherwise complete cache,
        // matching the runtime's explicit error rather than remote fallback.
        try Data("{}".utf8).write(to: bundle.appendingPathComponent("tokenizer.json"))
        #expect(!ready())
        try Data("{}".utf8).write(to: bundle.appendingPathComponent("tokenizer_config.json"))
        #expect(ready())
    }

    @Test func whisperTokenizerVariants() throws {
        #expect(try ManagedWhisperKit.tokenizerVariant(logits: 51864, embeddings: 384).description == "tiny.en")
        #expect(try ManagedWhisperKit.tokenizerVariant(logits: 51865, embeddings: 1280).description == "large-v2")
        #expect(try ManagedWhisperKit.tokenizerVariant(logits: 51866, embeddings: 1280).description == "large-v3")
        #expect(throws: (any Error).self) { try ManagedWhisperKit.tokenizerVariant(logits: 12, embeddings: 384) }
        #expect(throws: (any Error).self) { try ManagedWhisperKit.tokenizerVariant(logits: 51866, embeddings: 12) }
    }

    @Test func corruptWhisperTokenizerIsPreserved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-corrupt-tokenizer-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = Data("invalid tokenizer JSON".utf8)
        let tokenizerFile = directory.appendingPathComponent("tokenizer.json")
        try invalid.write(to: tokenizerFile)
        try Data(#"{"tokenizer_class":"WhisperTokenizer"}"#.utf8).write(to: directory.appendingPathComponent("tokenizer_config.json"))
        do {
            _ = try await LocalWhisperTokenizer.load(from: directory)
            Issue.record("Corrupt local tokenizer must fail without a fallback")
        } catch { }
        #expect(try Data(contentsOf: tokenizerFile) == invalid)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["tokenizer.json", "tokenizer_config.json"])
    }

    @Test func missingWhisperTokenizerFailsLocally() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-missing-tokenizer-\(UUID())")
        do {
            _ = try await LocalWhisperTokenizer.load(from: directory)
            Issue.record("Missing tokenizer must fail")
        } catch let error as LocalSpeechHelperLoader.MissingLocalModels {
            #expect(error.names == ["tokenizer.json", "tokenizer_config.json"])
        } catch { Issue.record("Unexpected error: \(error)") }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_LOCAL_WHISPER_TOKENIZER"] == "1"))
    func cachedWhisperTokenizerRoundTripsAndGroupsTokens() async throws {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/huggingface/models/openai/whisper-large-v3")
        let tokenizer = try await LocalWhisperTokenizer.load(from: folder)
        for text in ["Hello world!", "आज meeting 5 बजे है।", "你好世界", "A café costs €5."] {
            let tokens = tokenizer.tokenizer.encode(text: text, addSpecialTokens: false)
            #expect(tokenizer.decode(tokens: tokens) == text)
            let result = tokenizer.splitToWordTokens(tokenIds: tokens)
            #expect(result.wordTokens.flatMap { $0 } == tokens)
            #expect(result.words.joined() == text)
            let withSpecial = tokenizer.encode(text: text)
            let groupedSpecial = tokenizer.splitToWordTokens(tokenIds: withSpecial)
            #expect(groupedSpecial.wordTokens.flatMap { $0 } == withSpecial)
            #expect(groupedSpecial.words.joined() == tokenizer.decode(tokens: withSpecial))
        }
        #expect(tokenizer.specialTokens.timeTokenBegin == 50365)
        #expect(tokenizer.allLanguageTokens.contains(tokenizer.specialTokens.englishToken))
    }

    @Test func missingParakeetFilesFailLocally() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-missing-parakeet-\(UUID().uuidString)")
        for version in [AsrModelVersion.v2, .v3] {
            do {
                _ = try LocalSpeechHelperLoader.loadParakeet(directory: directory, version: version)
                Issue.record("Missing Parakeet must fail without downloading")
            } catch let error as LocalSpeechHelperLoader.MissingLocalModels {
                #expect(error.names.count == 5)
                #expect(error.names.contains(version == .v3 ? "JointDecisionv3.mlmodelc" : "JointDecision.mlmodelc"))
            } catch { Issue.record("Unexpected error: \(error)") }
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func localParakeetVocabularyValidation() throws {
        #expect(try LocalSpeechHelperLoader.parakeetVocabulary(Data(#"{"0":"<blank>","1":"hello"}"#.utf8)) == [0: "<blank>", 1: "hello"])
        for invalid in ["{}", #"{"bad":"hello"}"#, #"{"-1":"hello"}"#, #"{"1":"one","01":"duplicate"}"#] {
            #expect(throws: (any Error).self) { try LocalSpeechHelperLoader.parakeetVocabulary(Data(invalid.utf8)) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_LOCAL_HELPERS"] == "1"))
    func installedHelpersLoadThroughLocalOnlyAPIs() async throws {
        let policy = ModelNetworkPolicy(allowed: false)
        _ = try await LocalSpeechHelperLoader.loadVAD(networkPolicy: policy)
        _ = try await LocalSpeechHelperLoader.loadDiarizer(policy: .resolve(for: .current()), networkPolicy: policy)
        #expect(!policy.isAllowed)
    }

    @Test func missingOfflineHelpersDoNotDownloadOrCreateCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-missing-helpers-\(UUID().uuidString)")
        let policy = ModelNetworkPolicy(allowed: false)
        do {
            _ = try await LocalSpeechHelperLoader.loadVAD(networkPolicy: policy, directory: directory)
            Issue.record("Missing VAD must not trigger a download")
        } catch let error as LocalSpeechHelperLoader.MissingLocalModels {
            #expect(error.names.count == 1)
        }
        do {
            _ = try await LocalSpeechHelperLoader.loadDiarizer(policy: .resolve(for: .current()), networkPolicy: policy, directory: directory)
            Issue.record("Missing speaker models must not trigger a download")
        } catch let error as LocalSpeechHelperLoader.MissingLocalModels {
            #expect(error.names.count == 2)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func networkOperationCannotStartOffline() async {
        let policy = ModelNetworkPolicy(allowed: false)
        do {
            _ = try await policy.withNetworkAccess {
                Issue.record("Dependency-owned download must not start offline")
                return 1
            }
            Issue.record("Expected offline failure")
        } catch is ModelNetworkPolicy.OfflineError {
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func switchingOfflineCancelsDependencyOperation() async throws {
        let policy = ModelNetworkPolicy()
        let started = AsyncStream<Void>.makeStream()
        let task = Task {
            try await policy.withNetworkAccess {
                started.continuation.yield(())
                started.continuation.finish()
                try await Task.sleep(for: .seconds(10))
                return 1
            }
        }
        for await _ in started.stream { break }
        policy.setAllowed(false)
        do {
            _ = try await task.value
            Issue.record("Pending preparation should be cancelled")
        } catch is ModelNetworkPolicy.OfflineError {}
    }
}
