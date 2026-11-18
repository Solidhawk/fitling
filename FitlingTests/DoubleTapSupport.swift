import Testing
@testable import Fitling

/// Taps twice while the first request is still in flight and expects one call to `name`.
/// If the guard is missing, the second tap waits on the held call and the test's time limit fails it.
@MainActor
func expectSingleCall(_ name: String, on auth: FakeAuthProvider, tap: @escaping @MainActor @Sendable () async -> Void) async {
    auth.holdsCalls = true
    let first = Task { await tap() }
    while auth.calls[name] == nil {
        await Task.yield()
    }
    await tap()
    auth.releaseHeldCalls()
    await first.value
    auth.holdsCalls = false
    #expect(auth.calls[name] == 1)
}
