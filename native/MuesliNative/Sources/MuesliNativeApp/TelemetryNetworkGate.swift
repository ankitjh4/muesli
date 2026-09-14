import Foundation

/// A transport gate, not just a flag on new events. The telemetry SDK also
/// replays cached events on its own timer. Every SDK request must pass here.
final class TelemetryNetworkGate: @unchecked Sendable {
    static let shared = TelemetryNetworkGate()
    private let lock = NSLock()
    private let session: URLSession
    private var allowed = false
    private var tasks: [UUID: URLSessionDataTask] = [:]

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func setAllowed(_ value: Bool) {
        lock.lock()
        allowed = value
        let pending = value ? [] : Array(tasks.values)
        // Cancellation is requested while holding the admission lock: reopening
        // the gate cannot race ahead of cancellation of the previous generation.
        for task in pending { task.cancel() }
        lock.unlock()
    }

    @discardableResult
    func start(_ request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> UUID? {
        lock.lock()
        guard allowed else {
            lock.unlock()
            completion(nil, nil, URLError(.notConnectedToInternet))
            return nil
        }
        let id = UUID()
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let self {
                self.lock.lock()
                self.tasks.removeValue(forKey: id)
                self.lock.unlock()
            }
            completion(data, response, error)
        }
        tasks[id] = task
        task.resume()
        lock.unlock()
        return id
    }

    func cancel(_ id: UUID) {
        lock.lock()
        tasks[id]?.cancel()
        lock.unlock()
    }
}

/// Intercepts only the explicitly configured telemetry session. It is never
/// registered globally and therefore cannot alter local inference or other apps.
final class TelemetryTransportProtocol: URLProtocol, @unchecked Sendable {
    private let stateLock = NSLock()
    private var requestID: UUID?
    private var stopped = false

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryTransportProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = TelemetryNetworkGate.shared.start(request) { [weak self] data, response, error in
            guard let self else { return }
            self.stateLock.lock()
            let shouldDeliver = !self.stopped
            self.stateLock.unlock()
            guard shouldDeliver else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response { self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        stateLock.lock()
        requestID = id
        let shouldCancel = stopped
        stateLock.unlock()
        if shouldCancel, let id { TelemetryNetworkGate.shared.cancel(id) }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        let id = requestID
        stateLock.unlock()
        if let id { TelemetryNetworkGate.shared.cancel(id) }
    }
}
