import Foundation

/// The three states one async load can be in. A view keeps a single
/// `LoadState` per thing it loads rather than a parallel value +
/// `isLoading` + error triple, which is where "still loading" and "loaded
/// but empty" drift apart and start rendering the wrong placeholder.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(Error)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Runs `operation` and captures its outcome. Cancellation stays
    /// `.loading` — that means the work was superseded (a new `.task(id:)`
    /// generation, a screen popped), not that anything went wrong for the
    /// reader to see.
    static func load(_ operation: () async throws -> Value) async -> LoadState<Value> {
        do {
            return .loaded(try await operation())
        } catch is CancellationError {
            return .loading
        } catch {
            return .failed(error)
        }
    }
}
