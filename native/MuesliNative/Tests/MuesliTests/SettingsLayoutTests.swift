import AppKit
import SwiftUI
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Responsive settings", .serialized)
@MainActor
struct SettingsLayoutTests {
    @Test func controlsStayInsideNarrowSections() {
        for width in [280.0, 420.0, 520.0, 640.0, 880.0] {
            let layout = SettingsLayoutPolicy(availableWidth: width)
            #expect(layout.controlWidth(275) <= width - 2 * layout.pagePadding - 32)
            #expect(layout.controlWidth(220) <= 220)
        }
        #expect(SettingsLayoutPolicy(availableWidth: 280).stacksRows)
        #expect(!SettingsLayoutPolicy(availableWidth: 880).stacksRows)
        #expect(!SettingsLayoutPolicy(availableWidth: 760).usesSegmentedPicker)
        #expect(SettingsLayoutPolicy(availableWidth: 880).usesSegmentedPicker)
    }

    @Test func renderSettingsReviewSnapshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["MUESLI_UI_SNAPSHOT_DIR"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-settings-render-\(UUID().uuidString)")
        let store = DictationStore(databaseURL: support.appendingPathComponent("muesli.db"))
        try store.migrateIfNeeded()
        let controller = MuesliController(
            runtime: RuntimePaths(repoRoot: FileManager.default.temporaryDirectory, menuIcon: nil, appIcon: nil, bundlePath: nil),
            dictationStore: store,
            configStore: ConfigStore(supportDirectory: support)
        )
        for (name, pane, width) in [
            ("settings-general-narrow", SettingsPane.general, 280.0),
            ("settings-dictation-narrow", SettingsPane.dictation, 280.0),
            ("settings-dictation-wide", SettingsPane.dictation, 880.0),
            ("settings-appearance-narrow", SettingsPane.appearance, 280.0),
            ("settings-meetings-local-narrow", SettingsPane.meetings, 280.0),
            ("settings-meetings-online-narrow", SettingsPane.meetings, 280.0),
            ("settings-meetings-online-wide", SettingsPane.meetings, 880.0),
        ] {
            let online = name.contains("-online-")
            controller.updateConfig { $0.useOpenRouterForMeetings = online }
            controller.appState.selectedSettingsPane = pane
            let host = NSHostingView(rootView: SettingsView(appState: controller.appState, controller: controller).environment(\.colorScheme, .light))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            #expect(controller.appState.config.useOpenRouterForMeetings == online)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("\(name).png"))
            #expect(bitmap.pixelsWide >= Int(width))
            window.contentView = nil
        }
    }
}
