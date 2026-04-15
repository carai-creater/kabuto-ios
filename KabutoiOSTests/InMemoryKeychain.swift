import Foundation
@testable import KabutoiOS

/// Non-persistent KeychainStoring used in tests. Thread-safe via NSLock so
/// it's Sendable even under Swift 6 strict concurrency.
final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func set(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    func get(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
