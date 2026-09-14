import Foundation

/// Process-wide permission for model transfers and remote manifest discovery.
/// Local file validation is deliberately not gated: cached models stay usable.
public final class ModelNetworkPolicy: @unchecked Sendable {
    public static let shared = ModelNetworkPolicy()
    public struct OfflineError: LocalizedError, Sendable {
        public var errorDescription: String? {
            "Model downloads are paused in offline mode. Switch online to download missing files, then return offline."
        }
    }

    private let lock = NSLock()
    private var allowed: Bool
    private var cancellations: [UUID: @Sendable () -> Void] = [:]

    public init(allowed: Bool = true) { self.allowed = allowed }

    public var isAllowed: Bool {
        lock.lock(); defer { lock.unlock() }
        return allowed
    }

    public func setAllowed(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        allowed = value
        if !value { for cancel in cancellations.values { cancel() } }
    }

    public func requireAllowed() throws {
        lock.lock(); defer { lock.unlock() }
        guard allowed else { throw OfflineError() }
    }

    /// Admission and resume share the same lock as mode changes. Call finish
    /// once the consumer has unwound its delegate/file-writing work.
    public func resume(_ task: URLSessionTask, id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        guard allowed else { throw OfflineError() }
        cancellations[id] = { task.cancel() }
        task.resume()
    }

    public func finish(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        cancellations.removeValue(forKey: id)
    }

    private func startOperation<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) throws -> (UUID, Task<Value, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard allowed else { throw OfflineError() }
        let id = UUID()
        let task = Task {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        cancellations[id] = { task.cancel() }
        return (id, task)
    }

    public func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try await withNetworkAccess { try await session.data(for: request) }
    }

    /// Covers dependency-owned download operations that honor task cancellation,
    /// without changing their URLSession configuration or buffering model files.
    public func withNetworkAccess<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let (id, task) = try startOperation(operation)
        defer { finish(id) }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            // A mode change should be actionable, not shown as a connection
            // failure followed by automatic retry traffic.
            try requireAllowed()
            throw error
        }
    }
}
