import Foundation

@MainActor
func waitUntil(
    // 5s default (not 2s): under CI parallel + coverage load, a detached
    // `Task { @MainActor }` — e.g. WallpaperPresenter.loadWallpapers — can take
    // well over 2s to be scheduled, flaking positive polls. Explicit short
    // timeouts (negative assertions passing `.milliseconds(50)`) are unaffected.
    timeout: Duration = .seconds(5),
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
