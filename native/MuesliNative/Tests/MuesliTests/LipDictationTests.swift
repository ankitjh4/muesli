import Foundation
import AVFoundation
import CoreML
import CoreGraphics
import Testing
@testable import MuesliNativeApp

@Suite("Experimental lip dictation", .serialized)
@MainActor
struct LipDictationTests {
    @Test func lipSetupRequiresBothLocalStagesBeforeRecording() {
        #expect(LipModelStore.readiness(visualInstalled: true, languageInstalled: true, supportsLocalLanguage: true) == .ready)
        #expect(LipModelStore.readiness(visualInstalled: false, languageInstalled: true, supportsLocalLanguage: true) == .needsVisualModel)
        #expect(LipModelStore.readiness(visualInstalled: true, languageInstalled: false, supportsLocalLanguage: true) == .needsLanguageModel)
        #expect(LipModelStore.readiness(visualInstalled: false, languageInstalled: false, supportsLocalLanguage: true) == .needsVisualModel)
        #expect(LipModelStore.readiness(visualInstalled: true, languageInstalled: true, supportsLocalLanguage: false) == .unsupportedSystem)
    }

    @Test func cameraIsIdleUntilExplicitPreviewRequest() {
        let camera = LipCameraController()
        #expect(camera.phase == .idle)
        #expect(camera.previewSession == nil)
        #expect(camera.recordedVideoURL == nil)
        camera.record()
        camera.finish()
        #expect(camera.phase == .idle)
        camera.close()
        #expect(camera.previewSession == nil)
        #expect(camera.error == nil)
    }

    @Test func cameraAcceptsSuccessfulDurationLimitButRejectsFailures() {
        #expect(LipCameraController.recordingSucceeded(error: nil))
        #expect(LipCameraController.recordingSucceeded(error: NSError(domain: AVFoundationErrorDomain, code: -11810,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true])))
        #expect(!LipCameraController.recordingSucceeded(error: NSError(domain: AVFoundationErrorDomain, code: -1)))
        #expect(!LipCameraController.recordingSucceeded(error: NSError(domain: AVFoundationErrorDomain, code: -1,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false])))
    }

    @Test func nativeCTCDecoderMatchesPrototypeBlankAndRepeatRules() throws {
        var scores = [Float](repeating: -10, count: 320)
        for (step, label) in [16, 16, 0, 16, 18, 18, 0, 39].enumerated() {
            scores[step * 40 + label] = 10
        }
        #expect(try LipVisualModel.decodePhonemes(scores: scores) == ["HH", "HH", "IY", "ZH"])
        #expect(try LipVisualModel.decodePhonemes(scores: [Float](repeating: 0, count: 320)).isEmpty)
        // A tie must choose the first class rather than invent another phoneme.
        scores[16] = 10
        scores[0] = 10
        #expect(try LipVisualModel.decodePhonemes(scores: scores) == ["HH", "HH", "IY", "ZH"])
    }

    @Test func nativeCTCDecoderRejectsMalformedScores() {
        for count in [0, 40, 319, 321] {
            #expect(throws: LipDictationError.self) {
                try LipVisualModel.decodePhonemes(scores: [Float](repeating: 0, count: count))
            }
        }
        for invalid in [Float.nan, .infinity, -.infinity] {
            var scores = [Float](repeating: 0, count: 320)
            scores[42] = invalid
            #expect(throws: LipDictationError.self) { try LipVisualModel.decodePhonemes(scores: scores) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_NO_FACE_VIDEO"] != nil))
    func nativeImporterRejectsNoFaceVideo() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["MUESLI_TEST_NO_FACE_VIDEO"])
        do {
            _ = try await LipVideoInput.prepare(url: URL(fileURLWithPath: path))
            Issue.record("A no-face video must never reach inference")
        } catch LipVideoInput.InputError.insufficientFace { }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_NO_FACE_VIDEO"] != nil))
    func nativeSessionRejectsNoFaceWithoutEnglishGeneration() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["MUESLI_TEST_NO_FACE_VIDEO"])
        let session = LipDictationSession()
        session.startNative(video: URL(fileURLWithPath: path))
        try await waitForCompletion(session)
        #expect(session.error == LipVideoInput.InputError.insufficientFace.localizedDescription)
        #expect(session.result == nil)
        #expect(session.englishHypothesis.isEmpty)
    }

    @Test func nativeSessionCancellationDoesNotPublishResult() async throws {
        let session = LipDictationSession()
        session.startNative(video: URL(fileURLWithPath: "/nonexistent/video.mp4"))
        session.cancel()
        try await waitForCompletion(session)
        #expect(session.status == "Cancelled. Nothing was pasted or saved.")
        #expect(session.result == nil)
        #expect(session.error == nil)
        #expect(session.englishHypothesis.isEmpty)
    }

    @Test func nativeImporterRejectsRemoteVideo() async {
        do {
            _ = try await LipVideoInput.prepare(url: URL(string: "https://example.com/video.mp4")!)
            Issue.record("Remote video must not be fetched")
        } catch LipVideoInput.InputError.invalidVideo { }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func nativePipelineRejectsRemoteInputBeforeLoadingModel() async {
        do {
            _ = try await LipVisualModel.readVideo(
                url: URL(string: "https://example.com/video.mp4")!,
                compiledModelURL: URL(fileURLWithPath: "/nonexistent/model.mlmodelc"))
            Issue.record("Remote input must not reach the model")
        } catch LipVideoInput.InputError.invalidVideo { }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func nativeVideoSamplingIsBounded() throws {
        let times = try LipVideoInput.sampleTimes(duration: 4, frameRate: 30)
        #expect(times.count == 16)
        #expect(times.first == 0)
        #expect(times.last == 119.0 / 30)
        #expect(times == times.sorted())
        for (duration, fps) in [(0.0, 30.0), (11, 30), (0.1, 30), (4, .infinity), (4, 0), (.nan, 30), (4, Double.greatestFiniteMagnitude)] {
            #expect(throws: LipVideoInput.InputError.self) { try LipVideoInput.sampleTimes(duration: duration, frameRate: fps) }
        }
    }

    @Test func nativeFaceCropConvertsVisionCoordinatesAndClamps() throws {
        let upper = try LipVideoInput.cropRect(face: CGRect(x: 0.4, y: 0.7, width: 0.2, height: 0.2), width: 640, height: 480)
        #expect(upper.midY < 240)
        let full = try LipVideoInput.cropRect(face: CGRect(x: 0, y: 0, width: 1, height: 1), width: 640, height: 480)
        #expect(full == CGRect(x: 0, y: 0, width: 640, height: 480))
        #expect(throws: LipVideoInput.InputError.self) {
            try LipVideoInput.cropRect(face: CGRect(x: 2, y: 2, width: 0.1, height: 0.1), width: 640, height: 480)
        }
    }

    @Test func nativePixelsKeepRGBScale() throws {
        let data = Data([255, 20, 7, 255, 255, 20, 7, 255, 255, 20, 7, 255, 255, 20, 7, 255])
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let pixels = try LipVideoInput.rgbPixels(image: image, normalizedFace: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixels.count == 224 * 224 * 4)
        #expect(Array(pixels[0..<4]) == [255, 20, 7, 255])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MUESLI_TEST_VALLR_COREML"] != nil))
    func nativeCoreMLInferenceWithoutPython() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MUESLI_TEST_VALLR_COREML"])
        let model = try LipVisualModel(compiledModelURL: URL(fileURLWithPath: path), computeUnits: .cpuOnly)
        let video = try MLMultiArray(shape: LipVisualModel.inputShape.map(NSNumber.init), dataType: .float32)
        video.dataPointer.assumingMemoryBound(to: Float.self).update(repeating: 0, count: video.count)
        let scores = try model.predict(video: video)
        #expect(scores.count == 320)
        #expect(scores.allSatisfy { $0.isFinite })
        let invalid = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32)
        #expect(throws: LipDictationError.self) { try model.predict(video: invalid) }
    }

    private let validJSON = #"{"schema_version":1,"phonemes":["HH","IY"],"detected_frames":16,"sampled_frames":16,"device":"cpu"}"#

    @Test func validatesVersionAndFaceCounts() throws {
        let result = try LipDictationResult.decode(Data(validJSON.utf8))
        #expect(result.phonemes == ["HH", "IY"])
        #expect(throws: LipDictationError.self) {
            try LipDictationResult.decode(Data(validJSON.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":2").utf8))
        }
        #expect(throws: LipDictationError.self) {
            try LipDictationResult.decode(Data(validJSON.replacingOccurrences(of: "\"detected_frames\":16", with: "\"detected_frames\":17").utf8))
        }
    }

    @Test func missingRuntimeFailsWithoutStarting() {
        let session = LipDictationSession()
        session.start(folder: URL(fileURLWithPath: "/nonexistent/muesli-lip-test"), video: nil, reconstructEnglish: false)
        #expect(!session.isRunning)
        #expect(session.error?.contains("prepared VALLR") == true)
    }

    @Test func importsStructuredResultWithoutAutomaticReconstruction() async throws {
        let folder = try runtime(script: "#!/bin/sh\nprintf '%s' '\(validJSON)'\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = LipDictationSession()
        session.start(folder: folder, video: folder.appendingPathComponent("test.mp4"), reconstructEnglish: false)
        try await waitForCompletion(session)
        #expect(session.error == nil)
        #expect(session.result?.phonemes == ["HH", "IY"])
        #expect(session.englishHypothesis.isEmpty)
    }

    @Test func cancellationReapsRunningHelper() async throws {
        let folder = try runtime(script: "#!/bin/sh\nexec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = LipDictationSession()
        session.start(folder: folder, video: folder.appendingPathComponent("test.mp4"), reconstructEnglish: false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(session.isRunning)
        session.cancel()
        try await waitForCompletion(session)
        #expect(session.status.contains("Cancelled"))
        #expect(session.result == nil)
        #expect(session.error == nil)
    }

    @Test func noFaceDoesNotTriggerEnglishGuess() async throws {
        let json = validJSON.replacingOccurrences(of: "\"detected_frames\":16", with: "\"detected_frames\":0")
        let folder = try runtime(script: "#!/bin/sh\nprintf '%s' '\(json)'\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = LipDictationSession()
        session.start(folder: folder, video: folder.appendingPathComponent("test.mp4"), reconstructEnglish: true)
        try await waitForCompletion(session)
        #expect(session.error == nil)
        #expect(session.status.contains("Not enough usable lip movement"))
        #expect(session.englishHypothesis.isEmpty)
    }

    @Test func modelFailureIsVisible() async throws {
        let folder = try runtime(script: "#!/bin/sh\nprintf 'Invalid checkpoint' >&2\nexit 2\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = LipDictationSession()
        session.start(folder: folder, video: folder.appendingPathComponent("test.mp4"), reconstructEnglish: false)
        try await waitForCompletion(session)
        #expect(session.error?.contains("Invalid checkpoint") == true)
        #expect(session.result == nil)
    }

    private func runtime(script: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-lip-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".venv/bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".models"), withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent(".venv/bin/python")
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try Data().write(to: folder.appendingPathComponent(".models/VALLR.pth"))
        try Data().write(to: folder.appendingPathComponent("vallr_prototype.py"))
        return folder
    }

    private func waitForCompletion(_ session: LipDictationSession) async throws {
        for _ in 0..<100 where session.isRunning {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!session.isRunning)
        if session.isRunning { session.cancel() }
    }
}
