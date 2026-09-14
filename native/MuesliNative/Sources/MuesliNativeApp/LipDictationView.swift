import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LipDictationView: View {
    var onOpenModels: () -> Void = {}
    @State private var session = LipDictationSession()
    @State private var camera = LipCameraController()
    @State private var showDetails = false
    private var readiness: LipModelStore.Readiness { LipModelStore.readiness }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("EXPERIMENTAL · ENGLISH", systemImage: "flask")
                    .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.accent)
                Text("Speak silently").font(MuesliTheme.title1())
                Text("Turn a short phrase into text using lip movement. No microphone needed.")
                    .font(MuesliTheme.body()).foregroundStyle(MuesliTheme.textSecondary)
                VStack(alignment: .leading, spacing: 16) {
                    if readiness == .unsupportedSystem {
                        Label("Requires macOS 15 or later", systemImage: "desktopcomputer")
                            .font(MuesliTheme.headline())
                        Text("Suggested English text uses an on-device language model that needs a newer version of macOS.")
                    } else if readiness == .needsVisualModel {
                        Label("Lip reading isn’t downloaded yet", systemImage: "shippingbox")
                            .font(MuesliTheme.headline())
                        Text("We’re preparing the built-in download. You won’t need to install extra tools or configure anything yourself.")
                    } else if readiness == .needsLanguageModel {
                        Label("One more download before you begin", systemImage: "arrow.down.circle")
                            .font(MuesliTheme.headline())
                        Text("Lip reading is installed. Download the small local language model in Models → Quill to turn its output into suggested English text. Both stages stay on your Mac.")
                        Button("Open Models", action: onOpenModels)
                    } else {
                        Text("Choose a well-lit video with one person facing the camera and mouthing a short English phrase.")
                        HStack {
                            Button("Use camera") { camera.openPreview() }
                            Button("Choose video…", action: chooseVideo)
                        }.disabled(session.isRunning || (camera.phase != .idle && camera.phase != .failed))
                        Text("Imported videos can be up to 10 seconds. Camera clips stop after 8 seconds. Audio is never recorded.")
                            .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                    }
                    Text("Experimental results can be wrong. Always review the text before using it.")
                        .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                if let preview = camera.previewSession, camera.phase != .finished, camera.phase != .failed {
                    LipCameraPreview(session: preview)
                        .frame(height: 280).background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack {
                        if camera.phase == .preview {
                            Text("Position your face, then start recording.")
                            Spacer()
                            Button("Record clip") { camera.record() }
                        } else if camera.phase == .recording {
                            Label("Recording · 8 seconds maximum", systemImage: "record.circle")
                            Spacer()
                            Button("Finish & read lips") { camera.finish() }
                        } else {
                            ProgressView().controlSize(.small)
                            Text(camera.phase == .finishing ? "Finishing clip…" : "Preparing camera…")
                        }
                        Button("Close camera") { camera.close() }
                    }
                } else if camera.phase == .requesting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for camera access…")
                        Button("Cancel") { camera.close() }
                    }
                }
                if let cameraError = camera.error {
                    Text(cameraError).foregroundStyle(MuesliTheme.transcribing)
                }
                if session.isRunning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(session.status)
                        Spacer()
                        Button("Cancel") { session.cancel() }
                    }
                }
                if let error = session.error {
                    Text(error)
                        .foregroundStyle(MuesliTheme.transcribing)
                }
                if !session.englishHypothesis.isEmpty && !session.isRunning {
                    Text("Suggested text — please review").font(MuesliTheme.headline())
                    Text(session.englishHypothesis).textSelection(.enabled)
                    Button("Copy text") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.englishHypothesis, forType: .string)
                    }
                } else if session.result != nil && !session.isRunning && session.error == nil {
                    Text("Not enough clear lip movement. Try again with a short phrase.")
                }
                Text("Video is processed on your Mac. Nothing is pasted automatically or added to your history.")
                    .font(MuesliTheme.caption()).foregroundStyle(MuesliTheme.textSecondary)
                DisclosureGroup("About this experiment", isExpanded: $showDetails) {
                    Text("This research feature is not reliable for important messages or accessibility-critical communication. The public checkpoint lacks a trained text decoder; suggested text can be incorrect. Current model licensing permits non-commercial use only.")
                        .font(MuesliTheme.caption())
                    Link("Research and license", destination: URL(string: "https://github.com/MarshallT-99/VALLR")!)
                }
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .frame(maxWidth: 760, alignment: .leading).padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MuesliTheme.backgroundBase)
        .onChange(of: camera.recordedVideoURL) { _, url in
            if let url { session.startNative(video: url) }
        }
        .onChange(of: session.isRunning) { _, running in
            if !running, camera.recordedVideoURL != nil { camera.close() }
        }
        .onDisappear { session.cancel(); camera.close() }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a video up to 10 seconds long. Audio will not be used."
        NSApp.activate()
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                session.startNative(video: url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                session.startNative(video: url)
            }
        }
    }
}
