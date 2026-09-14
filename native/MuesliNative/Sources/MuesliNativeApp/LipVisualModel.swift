import CoreML
import Foundation

/// Native visual inference; no Python process or external environment.
/// Frame acquisition/cropping and text reconstruction are separate stages.
final class LipVisualModel {
    static let inputShape = [1, 16, 3, 224, 224]
    static let outputShape = [1, 8, 40]
    // Exact class order from the VALLR checkpoint. Class zero is the CTC blank.
    static let phonemeVocabulary = [
        "<pad>", "AA", "AE", "AH", "AO", "AW", "AY", "B", "CH", "D",
        "DH", "EH", "ER", "EY", "F", "G", "HH", "IH", "IY", "JH",
        "K", "L", "M", "N", "NG", "OW", "OY", "P", "R", "S",
        "SH", "T", "TH", "UH", "UW", "V", "W", "Y", "Z", "ZH"
    ]
    private let model: MLModel

    /// Local-only video pipeline. Call from a background task: Core ML prediction
    /// is synchronous. No audio is inspected and no English is invented here.
    static func readVideo(url: URL, compiledModelURL: URL) async throws -> LipDictationResult {
        try Task.checkCancellation()
        let prepared = try await LipVideoInput.prepare(url: url)
        try Task.checkCancellation()
        let visualModel = try LipVisualModel(compiledModelURL: compiledModelURL)
        try Task.checkCancellation()
        let scores = try visualModel.predict(video: prepared.video)
        try Task.checkCancellation()
        let phonemes = try decodePhonemes(scores: scores)
        return LipDictationResult(schemaVersion: 1, phonemes: phonemes,
                                  detectedFrames: prepared.detectedFrames,
                                  sampledFrames: inputShape[1], device: "Core ML")
    }

    /// Greedy CTC decoding, matching the research prototype. Adjacent repeated
    /// classes collapse, but a blank between repetitions preserves both sounds.
    /// These are phonemes, not words or a verified English transcription.
    static func decodePhonemes(scores: [Float]) throws -> [String] {
        guard scores.count == outputShape[1] * outputShape[2],
              scores.allSatisfy(\.isFinite) else { throw LipDictationError.invalidResult }
        var previous: Int?
        var phonemes: [String] = []
        for step in 0..<outputShape[1] {
            let offset = step * phonemeVocabulary.count
            var best = 0
            for candidate in 1..<phonemeVocabulary.count {
                // Strict comparison gives ties the first index, like torch.argmax.
                if scores[offset + candidate] > scores[offset + best] { best = candidate }
            }
            if best != 0, best != previous { phonemes.append(phonemeVocabulary[best]) }
            previous = best
        }
        return phonemes
    }

    init(compiledModelURL: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["video"]?.multiArrayConstraint?.shape.map(\.intValue) == Self.inputShape,
              model.modelDescription.outputDescriptionsByName["phoneme_logits"]?.multiArrayConstraint?.shape.map(\.intValue) == Self.outputShape else {
            throw LipDictationError.invalidResult
        }
    }

    /// Expects the exact prototype layout: 16 face crops, RGB float pixels in
    /// 0...255, channel-first. Values are model scores, not confidence estimates.
    func predict(video: MLMultiArray) throws -> [Float] {
        guard video.shape.map(\.intValue) == Self.inputShape, video.dataType == .float32 else {
            throw LipDictationError.invalidResult
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["video": MLFeatureValue(multiArray: video)])
        let output = try model.prediction(from: input)
        guard let scores = output.featureValue(for: "phoneme_logits")?.multiArrayValue,
              scores.shape.map(\.intValue) == Self.outputShape else { throw LipDictationError.invalidResult }
        let values = (0..<scores.count).map { scores[$0].floatValue }
        guard values.allSatisfy(\.isFinite) else { throw LipDictationError.invalidResult }
        return values
    }
}
