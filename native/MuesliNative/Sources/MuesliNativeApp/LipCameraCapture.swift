import AVFoundation
import Foundation
import Observation
import SwiftUI

/// Created only after the user chooses camera preview and grants video access.
/// All capture mutations and blocking start/stop calls use the serial queue.
private final class LipCameraWorker: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum Event: Sendable { case ready, recording, finished(URL), failed(String) }
    let captureSession = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.muesliplus.lip-camera")
    private let output = AVCaptureMovieFileOutput()
    private let event: @Sendable (Event) -> Void
    private var cancelled = false
    private var temporaryDirectory: URL?

    init(event: @escaping @Sendable (Event) -> Void) { self.event = event }

    func start() {
        queue.async {
            guard !self.cancelled else { return }
            do {
                guard let device = AVCaptureDevice.default(for: .video) else {
                    self.event(.failed("No camera is available. Connect a camera or choose a video instead.")); return
                }
                let input = try AVCaptureDeviceInput(device: device)
                self.captureSession.beginConfiguration()
                if self.captureSession.canSetSessionPreset(.vga640x480) {
                    self.captureSession.sessionPreset = .vga640x480
                }
                guard self.captureSession.canAddInput(input), self.captureSession.canAddOutput(self.output) else {
                    self.captureSession.commitConfiguration()
                    self.event(.failed("This camera could not be prepared. Choose a video instead.")); return
                }
                // Deliberately no audio device or audio input.
                self.captureSession.addInput(input)
                self.captureSession.addOutput(self.output)
                self.output.maxRecordedDuration = CMTime(seconds: 8, preferredTimescale: 600)
                self.output.maxRecordedFileSize = 32 * 1024 * 1024
                self.captureSession.commitConfiguration()
                self.captureSession.startRunning()
                self.event(self.captureSession.isRunning ? .ready : .failed("The camera couldn’t start. Close other camera apps and try again."))
            } catch {
                self.event(.failed("The camera couldn’t be opened. Check camera access in System Settings."))
            }
        }
    }

    func record() {
        queue.async {
            guard !self.cancelled, self.captureSession.isRunning, !self.output.isRecording,
                  self.temporaryDirectory == nil else { return }
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("muesli-lip-camera-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                       attributes: [.posixPermissions: 0o700])
                self.temporaryDirectory = directory
                self.output.startRecording(to: directory.appendingPathComponent("clip.mov"), recordingDelegate: self)
            } catch { self.event(.failed("There isn’t enough space to record a clip. Please try again.")) }
        }
    }

    func stopRecording() { queue.async { if self.output.isRecording { self.output.stopRecording() } } }

    func close() {
        queue.async {
            self.cancelled = true
            let recording = self.output.isRecording
            if recording { self.output.stopRecording() }
            self.captureSession.stopRunning()
            // Recording files are removed only after the writer has finished.
            if !recording { self.removeTemporaryRecording() }
        }
    }

    private func removeTemporaryRecording() {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
        temporaryDirectory = nil
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        queue.async { if !self.cancelled { self.event(.recording) } }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let successful = LipCameraController.recordingSucceeded(error: error)
        queue.async {
            self.captureSession.stopRunning()
            if self.cancelled { self.removeTemporaryRecording(); return }
            if successful { self.event(.finished(outputFileURL)) }
            else {
                self.removeTemporaryRecording()
                self.event(.failed("The recording couldn’t be saved. Try another short clip."))
            }
        }
    }
}

@MainActor @Observable
final class LipCameraController {
    enum Phase { case idle, requesting, preview, startingRecording, recording, finishing, finished, failed }
    private(set) var phase: Phase = .idle
    private(set) var previewSession: AVCaptureSession?
    private(set) var recordedVideoURL: URL?
    private(set) var error: String?
    @ObservationIgnored private var worker: LipCameraWorker?
    @ObservationIgnored private var generation = UUID()

    nonisolated static func recordingSucceeded(error: Error?) -> Bool {
        guard let error = error as NSError? else { return true }
        return (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
    }

    /// Never called on appearance. Permission and capture start require a click.
    func openPreview() {
        guard phase == .idle || phase == .failed else { return }
        close()
        phase = .requesting
        let request = generation
        Task {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard generation == request else { return }
            guard allowed else {
                error = "Allow camera access in System Settings → Privacy & Security → Camera, or choose a video instead."
                phase = .failed
                return
            }
            let worker = LipCameraWorker { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request else { return }
                    switch event {
                    case .ready: self.phase = .preview
                    case .recording: self.phase = .recording
                    case .finished(let url): self.recordedVideoURL = url; self.phase = .finished
                    case .failed(let message): self.error = message; self.phase = .failed; self.worker?.close()
                    }
                }
            }
            self.worker = worker
            previewSession = worker.captureSession
            worker.start()
        }
    }

    func record() {
        guard phase == .preview else { return }
        phase = .startingRecording
        worker?.record()
    }

    func finish() {
        guard phase == .recording else { return }
        phase = .finishing
        worker?.stopRecording()
    }

    func close() {
        generation = UUID()
        worker?.close()
        worker = nil
        previewSession = nil
        recordedVideoURL = nil
        phase = .idle
        error = nil
    }
}

struct LipCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        return view
    }
    func updateNSView(_ nsView: PreviewView, context: Context) { nsView.preview.session = session }
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) { nsView.preview.session = nil }

    final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            preview.videoGravity = .resizeAspect
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
