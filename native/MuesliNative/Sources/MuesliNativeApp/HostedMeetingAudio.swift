import AVFoundation
import Foundation

/// Reads the app's canonical 16 kHz mono recordings incrementally. Each request
/// contains at most one minute of audio, with no automatic retry or overlap.
enum HostedMeetingAudio {
    static func selection(config: AppConfig, apiKey: String) -> OpenRouterDictationConfiguration? {
        guard config.useOpenRouterForMeetings, !config.offlineInference else { return nil }
        return OpenRouterDictationConfiguration(apiKey: apiKey,
            model: config.openRouterMeetingModel.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static let maximumChunkFrames = 60 * 16_000

    struct PartialFailure: LocalizedError {
        let result: SpeechTranscriptionResult
        let completedThrough: TimeInterval
        let underlying: Error
        var errorDescription: String? {
            "Online transcription stopped partway through. The completed portion is available; the rest needs review or another transcription attempt."
        }
    }

    enum InputError: LocalizedError {
        case unsupportedAudio, emptyAudio
        var errorDescription: String? {
            switch self {
            case .unsupportedAudio: return "This recording needs conversion before online transcription. Import it through the app first."
            case .emptyAudio: return "The recording contains no audio."
            }
        }
    }

    static func transcribe(url: URL, configuration: OpenRouterDictationConfiguration,
                           client: OpenRouterTranscriptionClient,
                           chunkFrames: Int = maximumChunkFrames) async throws -> SpeechTranscriptionResult {
        try client.validateAccess(configuration: configuration)
        guard url.isFileURL, chunkFrames > 0, chunkFrames <= maximumChunkFrames else { throw InputError.unsupportedAudio }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.channelCount == 1, format.sampleRate == 16_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames)) else {
            throw InputError.unsupportedAudio
        }
        guard file.length > 0 else { throw InputError.emptyAudio }
        var segments: [SpeechSegment] = []
        var completedThrough: AVAudioFramePosition = 0
        do {
        while file.framePosition < file.length {
            try client.validateAccess(configuration: configuration)
            let start = file.framePosition
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(chunkFrames), file.length - start)))
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { throw InputError.unsupportedAudio }
            let values = Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
            guard values.allSatisfy(\.isFinite) else { throw InputError.unsupportedAudio }
            let part = try WavWriter.writeTemporaryWAV(samples: values, directoryName: "muesli-hosted-meeting")
            // This scope ends each iteration; only one temporary clip exists at a time.
            defer { try? FileManager.default.removeItem(at: part) }
            do {
                let response = try await client.transcribe(wavURL: part, configuration: configuration)
                try Task.checkCancellation()
                segments.append(SpeechSegment(start: Double(start) / 16_000,
                                              end: Double(file.framePosition) / 16_000,
                                              text: response.text))
            } catch OpenRouterTranscriptionError.emptyTranscript {
                // Silence may produce no words. Do not retry or invent text.
            }
            completedThrough = file.framePosition
        }
        try client.validateAccess(configuration: configuration)
        return SpeechTranscriptionResult(text: segments.map(\.text).joined(separator: " "), segments: segments)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            guard completedThrough > 0 else { throw error }
            throw PartialFailure(result: SpeechTranscriptionResult(text: segments.map(\.text).joined(separator: " "), segments: segments),
                                 completedThrough: Double(completedThrough) / 16_000, underlying: error)
        }
    }
}
