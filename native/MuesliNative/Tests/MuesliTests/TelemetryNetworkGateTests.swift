import Foundation
import Testing
@testable import MuesliNativeApp

private final class TelemetryTransportProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var completions = 0
    private var errorCode: Int?
    func started() { lock.lock(); starts += 1; lock.unlock() }
    func stopped() { lock.lock(); stops += 1; lock.unlock() }
    func completed(_ error: Error?) {
        lock.lock()
        completions += 1
        errorCode = (error as NSError?)?.code
        lock.unlock()
    }
    var snapshot: (starts: Int, stops: Int, completions: Int, errorCode: Int?) {
        lock.lock(); defer { lock.unlock() }
        return (starts, stops, completions, errorCode)
    }
}

private final class PendingTelemetryProtocol: URLProtocol, @unchecked Sendable {
    static let probe = TelemetryTransportProbe()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.probe.started() }
    override func stopLoading() { Self.probe.stopped() }
}

@Suite("Telemetry transport offline boundary", .serialized)
struct TelemetryNetworkGateTests {
    @Test func blocksCachedReplayCancelsPendingAndCanReopen() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingTelemetryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let gate = TelemetryNetworkGate(session: session)
        let completed = TelemetryTransportProbe()
        let initial = PendingTelemetryProtocol.probe.snapshot
        let request = URLRequest(url: URL(string: "https://telemetry.invalid/test")!)

        #expect(gate.start(request) { _, _, error in completed.completed(error) } == nil)
        #expect(completed.snapshot.errorCode == URLError.notConnectedToInternet.rawValue)
        #expect(PendingTelemetryProtocol.probe.snapshot.starts == initial.starts)

        gate.setAllowed(true)
        #expect(gate.start(request) { _, _, error in completed.completed(error) } != nil)
        for _ in 0..<100 where PendingTelemetryProtocol.probe.snapshot.starts < initial.starts + 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(PendingTelemetryProtocol.probe.snapshot.starts == initial.starts + 1)
        gate.setAllowed(false)
        for _ in 0..<100 where completed.snapshot.completions < 2 || PendingTelemetryProtocol.probe.snapshot.stops < initial.stops + 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(completed.snapshot.completions == 2)
        #expect(completed.snapshot.errorCode == URLError.cancelled.rawValue)
        #expect(PendingTelemetryProtocol.probe.snapshot.stops == initial.stops + 1)
        #expect(gate.start(request) { _, _, error in completed.completed(error) } == nil)
        #expect(PendingTelemetryProtocol.probe.snapshot.starts == initial.starts + 1)

        gate.setAllowed(true)
        let reopened = gate.start(request) { _, _, error in completed.completed(error) }
        #expect(reopened != nil)
        gate.setAllowed(false)
    }

    @Test func sdkSessionCannotBypassClosedGate() async throws {
        TelemetryNetworkGate.shared.setAllowed(false)
        let session = TelemetryTransportProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await session.data(from: URL(string: "https://telemetry.invalid/cached-event")!)
            Issue.record("Cached SDK requests must fail before reaching the network")
        } catch {
            #expect((error as NSError).code == URLError.notConnectedToInternet.rawValue)
        }
    }
}
