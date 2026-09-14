import CoreML
import FluidAudio
import Foundation
import MuesliCore

enum LocalSpeechHelperLoader {
    /// The app's managed downloader owns transfers and validation. Loading
    /// Parakeet must not hand control back to FluidAudio's repairing ModelHub.
    static func loadParakeet(directory: URL, version: AsrModelVersion) throws -> AsrModels {
        guard version == .v2 || version == .v3 else {
            throw AsrModelsError.loadingFailed("The local Parakeet loader supports v2 and v3 only.")
        }
        let names = ModelNames.ASR.self
        let jointName = version == .v3 ? names.jointV3File : names.jointFile
        let required = [names.preprocessorFile, names.encoderFile, names.decoderFile, jointName, names.vocabularyFile]
        try requireLocalFiles(required.map { directory.appendingPathComponent($0) })
        let vocabulary = try parakeetVocabulary(Data(contentsOf: directory.appendingPathComponent(names.vocabularyFile)))
        let configuration = AsrModels.defaultConfiguration()
        let preprocessorConfiguration = MLModelConfiguration()
        preprocessorConfiguration.computeUnits = .cpuOnly
        return try AsrModels(
            encoder: MLModel(contentsOf: directory.appendingPathComponent(names.encoderFile), configuration: configuration),
            preprocessor: MLModel(contentsOf: directory.appendingPathComponent(names.preprocessorFile), configuration: preprocessorConfiguration),
            decoder: MLModel(contentsOf: directory.appendingPathComponent(names.decoderFile), configuration: configuration),
            joint: MLModel(contentsOf: directory.appendingPathComponent(jointName), configuration: configuration),
            configuration: configuration,
            vocabulary: vocabulary,
            version: version
        )
    }

    static func parakeetVocabulary(_ data: Data) throws -> [Int: String] {
        let raw = try JSONDecoder().decode([String: String].self, from: data)
        var vocabulary: [Int: String] = [:]
        for (key, token) in raw {
            guard let index = Int(key), index >= 0, vocabulary[index] == nil else {
                throw AsrModelsError.loadingFailed("Parakeet vocabulary contains an invalid or duplicate token index.")
            }
            vocabulary[index] = token
        }
        guard !vocabulary.isEmpty else { throw AsrModelsError.loadingFailed("Parakeet vocabulary is empty.") }
        return vocabulary
    }

    struct MissingLocalModels: LocalizedError {
        let names: [String]
        var errorDescription: String? {
            "Local speech files are missing: \(names.joined(separator: ", ")). Prepare the speech models while online, then switch offline."
        }
    }

    static func requireLocalFiles(_ urls: [URL]) throws {
        let missing = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
        guard missing.isEmpty else { throw MissingLocalModels(names: missing.map(\.lastPathComponent)) }
    }

    static func loadDiarizer(
        policy: DiarizerRuntimePolicy,
        networkPolicy: ModelNetworkPolicy = .shared,
        directory: URL = DiarizerModels.defaultModelsDirectory()
    ) async throws -> DiarizerModels {
        if !networkPolicy.isAllowed {
            let segmentation = directory.appendingPathComponent(ModelNames.Diarizer.segmentationFile)
            let embedding = directory.appendingPathComponent(ModelNames.Diarizer.embeddingFile)
            try requireLocalFiles([segmentation, embedding])
            // Unlike load(from:), this overload never redownloads or deletes a
            // corrupt cache. Core ML errors are surfaced to the caller as-is.
            return try DiarizerModels.load(localSegmentationModel: segmentation,
                localEmbeddingModel: embedding, configuration: policy.modelConfiguration)
        }
        return try await networkPolicy.withNetworkAccess {
            try await DiarizerModels.download(to: directory, configuration: policy.modelConfiguration)
        }
    }

    static func loadVAD(
        networkPolicy: ModelNetworkPolicy = .shared,
        directory: URL = MLModelConfigurationUtils.defaultModelsDirectory(for: .vad)
    ) async throws -> VadManager {
        if !networkPolicy.isAllowed {
            let url = directory.appendingPathComponent(ModelNames.VAD.sileroVadFile)
            try requireLocalFiles([url])
            let model = try MLModel(contentsOf: url,
                configuration: MLModelConfigurationUtils.defaultConfiguration(computeUnits: VadConfig.default.computeUnits))
            return VadManager(vadModel: model)
        }
        return try await networkPolicy.withNetworkAccess { try await VadManager() }
    }
}
