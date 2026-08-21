import Foundation

extension String {
    /// FNV-1a, 64-bit. A hash that means the same thing in every process
    /// that ever runs this app.
    ///
    /// Swift's own `hashValue` is seeded per launch, which is a security
    /// property and a correctness problem for both callers here: one names
    /// cache files that have to be found again after a relaunch, the other
    /// picks what Home features today and has to pick the same thing when
    /// the app is reopened an hour later. Neither wants a hash that
    /// changes when the process does.
    ///
    /// FNV-1a rather than anything stronger because neither use is
    /// adversarial — these are labels and dice, not signatures.
    var fnv1aHash: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
