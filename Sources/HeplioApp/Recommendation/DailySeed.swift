import Foundation

/// The dice Home rolls each morning.
///
/// Home has to change day to day without becoming unstable *within* a
/// day: a reader who reopens the app after lunch should find the shelf
/// they were halfway through, not a reshuffled one. The obvious way to
/// get that is to store what was picked — and that's exactly what this
/// app can't do, because the store is destined for iCloud and an
/// algorithm's scratch paper is not something worth syncing.
///
/// So nothing is stored. The seed is a pure function of the local
/// calendar day and a per-shelf salt, which gives all three properties at
/// once: stable through the day, different tomorrow, and identical on two
/// devices that never exchanged a byte about it.
struct DailySeed {
    private let seed: UInt64

    /// - Parameters:
    ///   - day: The local day, as INSPIRE's `yyyy-MM-dd`. Local on
    ///     purpose — the day should turn over at the reader's midnight,
    ///     the same way `NewFeedSelection`'s window does.
    ///   - salt: Distinguishes one use from another, so two shelves
    ///     drawing from the same list on the same day don't draw the same
    ///     order.
    init(day: String = Date.now.inspireDay, salt: String) {
        self.seed = "\(day)|\(salt)".fnv1aHash
    }

    /// A fresh generator. Handed out rather than held, because
    /// `RandomNumberGenerator` mutates as it runs and a `DailySeed` has to
    /// stay a value that answers the same way every time it's asked.
    var generator: SeededGenerator { SeededGenerator(seed: seed) }

    /// A deterministic shuffle of `elements`.
    func shuffled<T>(_ elements: [T]) -> [T] {
        var rng = generator
        return elements.shuffled(using: &rng)
    }

    /// Picks `count` elements, favouring the ones with the higher weight
    /// but never guaranteeing them — which is the whole point. Taking the
    /// top `count` of a ranked list would be stable *and* identical every
    /// day; sampling from a deeper pool keeps the good ones likely and
    /// still lets today differ from yesterday.
    ///
    /// Weighted sampling without replacement, by the exponential-race
    /// trick: give each element a key of `-ln(u) / weight` and take the
    /// smallest. Non-positive weights are dropped rather than clamped —
    /// a zero-weight candidate is one the caller has said doesn't belong.
    func sample<T>(_ elements: [T], count: Int, weight: (T) -> Double) -> [T] {
        guard count < elements.count else { return shuffled(elements) }
        var rng = generator
        return elements
            .compactMap { element -> (T, Double)? in
                let w = weight(element)
                guard w > 0 else { return nil }
                let u = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &rng)
                return (element, -log(u) / w)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(count)
            .map(\.0)
    }

    /// One element, or nil from an empty list. What picks the day's
    /// "Because You Read *X*".
    func pick<T>(_ elements: [T]) -> T? {
        var rng = generator
        return elements.randomElement(using: &rng)
    }
}

/// SplitMix64 — a seeded `RandomNumberGenerator`.
///
/// The standard library's `SystemRandomNumberGenerator` can't be seeded,
/// which is the one thing needed here. SplitMix64 is the usual choice for
/// this: it's a handful of arithmetic, it takes any seed including zero,
/// and its output quality is far beyond what shuffling a dozen shelves
/// asks of it.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
