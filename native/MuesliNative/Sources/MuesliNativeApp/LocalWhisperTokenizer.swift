// Word grouping follows WhisperKit's WhisperTokenizerWrapper.
// MIT License — Copyright (c) 2024 argmax, inc.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import NaturalLanguage
import MuesliCore
import WhisperKit

/// Only the local-folder parser is used here. Invalid files never fall through
/// to WhisperKit's remote tokenizer loader.
struct LocalWhisperTokenizer: WhisperTokenizer {
    let tokenizer: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    static func load(from directory: URL) async throws -> LocalWhisperTokenizer {
        try LocalSpeechHelperLoader.requireLocalFiles(["tokenizer.json", "tokenizer_config.json"].map {
            directory.appendingPathComponent($0)
        })
        return try await LocalWhisperTokenizer(tokenizer: AutoTokenizerWrapper.from(modelFolder: directory))
    }

    init(tokenizer: TokenizerWrapper) throws {
        self.tokenizer = tokenizer
        func required(_ text: String) throws -> Int {
            guard let value = tokenizer.convertTokenToId(text) else {
                throw WhisperError.tokenizerUnavailable()
            }
            return value
        }
        specialTokens = try SpecialTokens(
            endToken: required("<|endoftext|>"), englishToken: required("<|en|>"),
            noSpeechToken: required("<|nospeech|>"), noTimestampsToken: required("<|notimestamps|>"),
            specialTokenBegin: required("<|endoftext|>"), startOfPreviousToken: required("<|startofprev|>"),
            startOfTranscriptToken: required("<|startoftranscript|>"), timeTokenBegin: required("<|0.00|>"),
            transcribeToken: required("<|transcribe|>"), translateToken: required("<|translate|>"),
            whitespaceToken: required("Ġ")
        )
        let boundary = specialTokens.specialTokenBegin
        allLanguageTokens = Set(Constants.languages.values.compactMap { tokenizer.convertTokenToId("<|\($0)|>") }
            .filter { $0 > boundary })
    }

    func encode(text: String) -> [Int] { tokenizer.encode(text: text) }
    func decode(tokens: [Int]) -> String { tokenizer.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { tokenizer.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { tokenizer.convertIdToToken(id) }

    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(decode(tokens: tokenIds.filter { $0 < specialTokens.specialTokenBegin }))
        let noSpaces = ["zh", "ja", "th", "lo", "my", "yue"].contains(recognizer.dominantLanguage?.rawValue)
        var words: [String] = []
        var groups: [[Int]] = []
        var pending: [Int] = []
        for (index, token) in tokenIds.enumerated() {
            pending.append(token)
            let text = decode(tokens: pending)
            // Byte-level BPE can divide a Unicode scalar across tokens.
            if text.contains("\u{fffd}") && index < tokenIds.count - 1 { continue }
            let punctuation = UnicodeScalar(text.trimmingCharacters(in: .whitespaces))
                .map { CharacterSet.punctuationCharacters.contains($0) } ?? false
            if noSpaces || words.isEmpty || pending[0] >= specialTokens.specialTokenBegin || text.hasPrefix(" ") || punctuation {
                words.append(text)
                groups.append(pending)
            } else {
                words[words.count - 1] += text
                groups[groups.count - 1].append(contentsOf: pending)
            }
            pending = []
        }
        return (words, groups)
    }
}

/// Replaces only tokenizer loading; Core ML inference remains WhisperKit's.
final class ManagedWhisperKit: WhisperKit {
    // The superclass's private-set modelVariant is only updated by its remote-
    // capable tokenizer loader. Consumers must use this resolved value instead.
    private(set) var loadedTokenizerVariant: ModelVariant?

    static func variantForAppModel(_ name: String) -> ModelVariant? {
        let normalized = name.hasPrefix("openai_whisper-") ? String(name.dropFirst("openai_whisper-".count)) : name
        if normalized == BackendOption.whisperLargeTurbo.model || normalized == ManagedASRModelPlans.hinglishWhisperKitModelName {
            return .largev3
        }
        return ModelVariant.allCases.first { $0.description == normalized }
    }

    static func tokenizerPlan(for variant: ModelVariant, cacheRoot: URL? = nil) -> ManagedASRModelPlan {
        let repository = "openai/whisper-\(variant.description)"
        let root = cacheRoot ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/huggingface/models")
        let files = ["tokenizer.json", "tokenizer_config.json"]
        return ManagedASRModelPlan(
            modelID: "whisper-tokenizer-\(variant.description)", repository: repository,
            cacheDirectory: root.appendingPathComponent(repository),
            selections: [HuggingFaceModelSelection(includedPaths: Set(files))],
            requiredArtifactAlternatives: files.map { [$0] }
        )
    }

    static func tokenizerFilesReady(modelName: String, modelFolder: URL? = nil, cacheRoot: URL? = nil) -> Bool {
        let folder = modelFolder ?? ManagedASRModelPlans.whisperKit(modelName: modelName).cacheDirectory
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("tokenizer.json").path) {
            return FileManager.default.fileExists(atPath: folder.appendingPathComponent("tokenizer_config.json").path)
        }
        guard let variant = variantForAppModel(modelName) else { return false }
        return tokenizerPlan(for: variant, cacheRoot: cacheRoot).isAvailableLocally()
    }

    static func prepareTokenizer(modelName: String) async throws {
        let folder = ManagedASRModelPlans.whisperKit(modelName: modelName).cacheDirectory
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("tokenizer.json").path) {
            _ = try await LocalWhisperTokenizer.load(from: folder)
            return
        }
        guard let variant = variantForAppModel(modelName) else { throw WhisperError.tokenizerUnavailable() }
        _ = try await ManagedASRModelDownloader.loadValidated(tokenizerPlan(for: variant)) {
            try await LocalWhisperTokenizer.load(from: $0)
        }
    }

    static func tokenizerVariant(logits: Int, embeddings: Int) throws -> ModelVariant {
        if logits == 51866 && embeddings == 1280 { return .largev3 }
        let multilingual: [Int: ModelVariant] = [384: .tiny, 512: .base, 768: .small, 1024: .medium, 1280: .largev2]
        let english: [Int: ModelVariant] = [384: .tinyEn, 512: .baseEn, 768: .smallEn, 1024: .mediumEn]
        guard let variant = (logits == 51865 ? multilingual : logits == 51864 ? english : [:])[embeddings] else {
            throw WhisperError.tokenizerUnavailable()
        }
        return variant
    }

    override func loadTokenizerIfNeeded() async throws {
        guard tokenizer == nil else { return }
        guard let logits = textDecoder.logitsSize, let embeddings = audioEncoder.embedSize else {
            throw WhisperError.tokenizerUnavailable()
        }
        let variant = try Self.tokenizerVariant(logits: logits, embeddings: embeddings)
        textDecoder.isModelMultilingual = variant.isMultilingual
        // Honor bundled tokenizer files before the shared managed cache. A
        // corrupt bundle is an error, never grounds for a hidden remote retry.
        if let modelFolder,
           FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("tokenizer.json").path) {
            tokenizer = try await LocalWhisperTokenizer.load(from: modelFolder)
            loadedTokenizerVariant = variant
            return
        }
        let plan = Self.tokenizerPlan(for: variant)
        tokenizer = try await ManagedASRModelDownloader.loadValidated(plan) { folder in
            try await LocalWhisperTokenizer.load(from: folder)
        }
        loadedTokenizerVariant = variant
    }
}
