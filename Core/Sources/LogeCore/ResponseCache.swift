import Foundation

/// Recent responses by key, in bounded process memory only. Lookups while a fetch runs join
/// it, and a cancelled screen cannot cancel the shared request or discard its result while
/// another screen or prefetch still needs it. Failures aren't kept, so Retry asks again.
actor ResponseCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        var value: Value
        var expiresAt: ContinuousClock.Instant
    }
    private struct Flight {
        var id: UUID
        var task: Task<Value, Error>
    }
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Flight] = [:]
    private let capacity: Int
    private let lifetime: Duration
    private let keeps: @Sendable (Value) -> Bool

    /// `keeps` decides which successful values are worth keeping; the rest are fetched again.
    init(capacity: Int, lifetime: Duration, keeps: @escaping @Sendable (Value) -> Bool = { _ in true }) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
        self.keeps = keeps
    }

    func value(for key: Key, fetch: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let entry = entries[key], entry.expiresAt > ContinuousClock.now { return entry.value }
        entries[key] = nil
        let flight: Flight
        if let pending = inFlight[key] {
            flight = pending
        } else {
            flight = Flight(id: UUID(), task: Task { try await fetch() })
            inFlight[key] = flight
        }
        do {
            let value = try await flight.task.value
            if inFlight[key]?.id == flight.id {
                inFlight[key] = nil
                if keeps(value) {
                    let now = ContinuousClock.now
                    entries = entries.filter { $0.value.expiresAt > now }
                    entries[key] = Entry(value: value, expiresAt: now + lifetime)
                    if entries.count > capacity, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                        entries[oldest] = nil
                    }
                }
            }
            // Store a successful shared response even if this particular waiter left.
            try Task.checkCancellation()
            return value
        } catch {
            if inFlight[key]?.id == flight.id { inFlight[key] = nil }
            throw error
        }
    }
}
