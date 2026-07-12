# config ホットリロード PR1（中核）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** config を単一のリアクティブな source of truth にし、`config.toml` の変更をファイル監視で検知して daemon 再起動なしに再読込・適用する中核を作る。不正 config は前回値を保持し、崩れた測地線球体でグラフィカルに通知する。

**Architecture:** `ConfigUseCase` の `lazy var` 凍結をロック付き store + `reload()` に置換（変更は 1 ファイルに限定）。新設 `ConfigWatchGateway`（Domain protocol + 専用ライブ実装、`ProcessGateway`/`SignalTerminationHandler` の DispatchSource パターン踏襲）を新設 `ConfigInteractor`（`ScreenInteractor` 踏襲）が駆動し、debounce して `reload()` を叩く。`.updated` は各 Presenter へ Void ping（本 PR では pull 消費者=spectrum/ripple 見た目・screen が自動追従）、`.invalid` は `ConfigStatusPresenter` → `ConfigStatusOverlay`（崩れた球体）へ。lyrics DataSource の init 焼付も毎回読みに直す。

**Tech Stack:** Swift 6 / swift-dependencies / Combine / `OSAllocatedUnfairLock`(os) / `DispatchSource.makeFileSystemObjectSource`(Dispatch) / SwiftUI Canvas / swift-testing。

**参照する既存パターン（実装時に必ず開いて合わせる）:**

- Gateway protocol: `Sources/Domain/Misc/ProcessGateway.swift`
- DispatchSource ラップ（backend + source + fake 可能）: `Sources/App/SignalTerminationHandler.swift`
- Interactor + Publisher + start/stop: `Sources/Domain/Interactor/ScreenInteractor.swift` / `Sources/ScreenInteractor/ScreenInteractorImpl.swift`
- 監視 Task ライフサイクル（clock 注入・stop で cancel・deinit 保険）: `Sources/Presenters/App/AppPresenter.swift`, `Sources/Presenters/Wallpaper/WallpaperPresenter.swift:47-96`
- ロック付き可変状態: `Sources/SpectrumInteractor/SpectrumInteractorImpl.swift`（`OSAllocatedUnfairLock`）
- ローディングオーバーレイ（条件付き挿入・#252）: `Sources/Views/Overlay/OverlayContentView.swift:47-96`
- 測地線球体: `Sources/Views/Overlay/OverlayContentView.swift:98-194`, `Sources/Views/Overlay/GeodesicGeometry.swift`
- lyrics 毎回読み手本: `Sources/MetadataDataSource/LLMMetadataDataSourceImpl.swift:34-36`
- DI 登録: `Sources/DependencyInjection/GatewayRegistration.swift` / `InteractorRegistration.swift`
- パイプライン E2E の土台（`withDependencies` グラフ・temp config・`render()`）: `Tests/ConfigUseCaseTests/ConfigUseCaseTests.swift`, `Tests/ViewsTests/ViewRenderingTests.swift`

---

## ファイル構成

### 新規（Entity・純粋データ）

- `Sources/Entity/Config/ConfigReloadOutcome.swift` — `ConfigReloadOutcome` enum
- `Sources/Entity/Config/ConfigReloadFailure.swift` — `ConfigReloadFailure` struct + `reason` enum

### 新規（Domain・契約 / coverage 除外）

- `Sources/Domain/Misc/ConfigWatchGateway.swift` — protocol + `ConfigWatchToken` + DI key + Unimplemented
- `Sources/Domain/Interactor/ConfigInteractor.swift` — protocol + DI key + Unimplemented

### 新規（covered 実装モジュール）

- `Sources/FileWatchGateway/FileWatchGateway.swift` — `ConfigWatchGateway` ライブ実装（DispatchSource dir 監視）
- `Sources/ConfigInteractor/ConfigInteractorImpl.swift` — `ConfigInteractor` ライブ実装
- `Tests/FileWatchGatewayTests/…` / `Tests/ConfigInteractorTests/…`

### 変更

- `Sources/ConfigUseCase/ConfigUseCaseImpl.swift` — 凍結 → store + `reload()`
- `Sources/Domain/UseCase/ConfigUseCase.swift` — protocol に `reload()` 追加 + Unimplemented 更新
- `Sources/LyricsDataSource/CustomScriptLyricsDataSourceImpl.swift` — init 焼付 → 毎回読み
- `Sources/Presenters/Config/ConfigStatusPresenter.swift` — 新規 Presenter
- `Sources/Views/Overlay/ConfigStatusOverlay.swift` — 新規 View（崩れた球体）
- `Sources/Views/Overlay/OverlayContentView.swift` — `ConfigStatusOverlay` を ZStack に追加
- `Sources/Views/Overlay/GeodesicGeometry.swift` — 破断表現に必要なら edge メタ露出（球体再利用時に確認）
- `Sources/AppRouter/AppRouter.swift` — `ConfigInteractor` start/stop + `ConfigStatusPresenter` 生成・注入
- `Sources/DependencyInjection/GatewayRegistration.swift` — `ConfigWatchGatewayKey.liveValue`
- `Sources/DependencyInjection/InteractorRegistration.swift` — `ConfigInteractorKey.liveValue`
- `Package.swift` — `FileWatchGateway` / `ConfigInteractor` の target・testTarget、`Presenters`/`Views`/`DependencyInjection`/`AppRouter` の依存追加
- `Tests/ConfigUseCaseTests/ConfigUseCaseTests.swift` — `appStyleCachedSingleRead` を reload 契約に書き換え

---

## Task A: Entity — reload の結果型

**Files:**

- Create: `Sources/Entity/Config/ConfigReloadOutcome.swift`
- Create: `Sources/Entity/Config/ConfigReloadFailure.swift`
- Test: `Tests/EntityTests/ConfigReloadOutcomeTests.swift`（存在しなければ新規。Entity は純粋データなので最小限の構築テストのみ）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// Tests/EntityTests/ConfigReloadOutcomeTests.swift
import Testing
@testable import Entity

@Suite("ConfigReloadOutcome")
struct ConfigReloadOutcomeTests {
    @Test("updated carries the new style")
    func updatedCarriesStyle() {
        let style = AppStyle(configDir: "/tmp")
        let outcome = ConfigReloadOutcome.updated(style)
        guard case .updated(let s) = outcome else { Issue.record("expected .updated"); return }
        #expect(s.configDir == "/tmp")
    }

    @Test("invalid carries path and reason")
    func invalidCarriesFailure() {
        let outcome = ConfigReloadOutcome.invalid(.init(path: "/c.toml", reason: .decode("bad")))
        guard case .invalid(let f) = outcome else { Issue.record("expected .invalid"); return }
        #expect(f.path == "/c.toml")
        #expect(f.reason == .decode("bad"))
    }
}
```

- [ ] **Step 2: 失敗を確認** — Run: `swift test --filter ConfigReloadOutcomeTests` / Expected: FAIL（型未定義）

- [ ] **Step 3: 実装（純粋データのみ・ロジック無し）**

```swift
// Sources/Entity/Config/ConfigReloadFailure.swift
public struct ConfigReloadFailure: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case unreadable
        case decode(String)
    }
    public let path: String
    public let reason: Reason
    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }
}
```

```swift
// Sources/Entity/Config/ConfigReloadOutcome.swift
public enum ConfigReloadOutcome: Sendable {
    case updated(AppStyle)
    case invalid(ConfigReloadFailure)
}
```

- [ ] **Step 4: 成功を確認** — Run: `swift test --filter ConfigReloadOutcomeTests` / Expected: PASS
- [ ] **Step 5: commit** — `git add -A && git commit -m "feat(#41): reload 結果型 ConfigReloadOutcome/Failure を追加"`

---

## Task B: ConfigUseCase — 凍結を store + reload() に置換

**Files:**

- Modify: `Sources/Domain/UseCase/ConfigUseCase.swift`（protocol に `reload()` 追加、Unimplemented 更新）
- Modify: `Sources/ConfigUseCase/ConfigUseCaseImpl.swift`
- Modify: `Tests/ConfigUseCaseTests/ConfigUseCaseTests.swift`（`appStyleCachedSingleRead` を書き換え、reload テスト追加）

- [ ] **Step 1: 失敗するテストを書く**（既存 `appStyleCachedSingleRead` を削除し以下を追加。`MockConfigRepository`/`CountingConfigRepository` に `validate()` の戻り値を制御できるよう `validation:` フィールドを足す）

```swift
// MockConfigRepository に追加: var validation: ConfigValidationResult = .defaults ; func validate() -> ... { validation }
// CountingConfigRepository に追加: var validation: ConfigValidationResult = .loaded(path: "/c.toml"); var pathExists = true;
//   func validate() -> ... { validation }; var existingConfigPath: String? { pathExists ? "/c.toml" : nil }

@Test("appStyle は初回に一度ロードされキャッシュされる")
func appStyleLoadsOnceThenCaches() {
    let counter = CountingConfigRepository()
    withDependencies { $0.configRepository = counter } operation: {
        let useCase = ConfigUseCaseImpl()
        _ = useCase.appStyle; _ = useCase.appStyle
        #expect(counter.callCount == 1)
    }
}

@Test("reload はディスクを再読込し .updated を返す")
func reloadUpdatesFromDisk() {
    let counter = CountingConfigRepository()
    counter.validation = .loaded(path: "/c.toml")
    withDependencies { $0.configRepository = counter } operation: {
        let useCase = ConfigUseCaseImpl()
        _ = useCase.appStyle              // 初回ロード（count 1）
        let outcome = useCase.reload()    // 再ロード（count 2）
        #expect(counter.callCount == 2)
        guard case .updated = outcome else { Issue.record("expected .updated"); return }
    }
}

@Test("decodeError では前回値を保持し .invalid を返す")
func reloadKeepsPreviousOnDecodeError() {
    let counter = CountingConfigRepository()
    counter.validation = .decodeError(path: "/c.toml", error: "syntax")
    withDependencies { $0.configRepository = counter } operation: {
        let useCase = ConfigUseCaseImpl()
        _ = useCase.appStyle              // count 1
        let outcome = useCase.reload()    // validate 失敗 → loadAppStyle 呼ばない（count 1 のまま）
        #expect(counter.callCount == 1)
        guard case .invalid(let f) = outcome else { Issue.record("expected .invalid"); return }
        #expect(f.reason == .decode("syntax"))
    }
}

@Test("ファイル存在下の .defaults は読取失敗とみなし前回値保持")
func reloadTreatsDefaultsWithExistingFileAsUnreadable() {
    let counter = CountingConfigRepository()
    counter.validation = .defaults
    counter.pathExists = true
    withDependencies { $0.configRepository = counter } operation: {
        let useCase = ConfigUseCaseImpl()
        _ = useCase.appStyle
        let outcome = useCase.reload()
        guard case .invalid(let f) = outcome else { Issue.record("expected .invalid"); return }
        #expect(f.reason == .unreadable)
    }
}

@Test("ファイル不在の .defaults は正当なデフォルト適用として .updated")
func reloadAppliesDefaultsWhenNoFile() {
    let counter = CountingConfigRepository()
    counter.validation = .defaults
    counter.pathExists = false
    withDependencies { $0.configRepository = counter } operation: {
        let useCase = ConfigUseCaseImpl()
        _ = useCase.appStyle
        let outcome = useCase.reload()
        guard case .updated = outcome else { Issue.record("expected .updated"); return }
    }
}
```

- [ ] **Step 2: 失敗を確認** — Run: `swift test --filter ConfigUseCaseTests` / Expected: FAIL（`reload` 未定義）

- [ ] **Step 3: protocol と Impl を実装**

```swift
// Sources/Domain/UseCase/ConfigUseCase.swift — protocol に追加
func reload() -> ConfigReloadOutcome
// UnimplementedConfigUseCase に追加:
func reload() -> ConfigReloadOutcome { .updated(.init()) }
```

```swift
// Sources/ConfigUseCase/ConfigUseCaseImpl.swift 全置換
import Dependencies
import Domain
import os

public final class ConfigUseCaseImpl: @unchecked Sendable {
    @Dependency(\.configRepository) private var repository
    private let store: OSAllocatedUnfairLock<AppStyle>

    public init() {
        @Dependency(\.configRepository) var repository
        // 起動時に一度ロード（従来の lazy 初回ロードと同挙動、ただし可変 store に保持）
        store = OSAllocatedUnfairLock(initialState: repository.loadAppStyle())
    }
}

extension ConfigUseCaseImpl: ConfigUseCase {
    public var appStyle: AppStyle { store.withLock { $0 } }

    public func reload() -> ConfigReloadOutcome {
        let fileExists = repository.existingConfigPath != nil
        switch repository.validate() {
        case .loaded:
            let style = repository.loadAppStyle()
            store.withLock { $0 = style }
            return .updated(style)
        case .defaults where !fileExists:
            let style = repository.loadAppStyle()
            store.withLock { $0 = style }
            return .updated(style)
        case .defaults:
            // ファイルは在るが tryDecode が "" を返した = 読取失敗（atomic-save 中等）→ 前回値保持
            return .invalid(.init(path: repository.existingConfigPath ?? "", reason: .unreadable))
        case .unreadable(let path):
            return .invalid(.init(path: path, reason: .unreadable))
        case .decodeError(let path, let error):
            return .invalid(.init(path: path, reason: .decode(error)))
        }
    }

    public func template(format: ConfigFormat) -> String? { repository.template(format: format) }
    public func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        try repository.writeTemplate(format: format, force: force)
    }
    public var existingConfigPath: String? { repository.existingConfigPath }
}
```

- [ ] **Step 4: 成功を確認** — Run: `swift test --filter ConfigUseCaseTests` / Expected: PASS（既存の delegate テスト群も緑のまま）
- [ ] **Step 5: commit** — `git add -A && git commit -m "feat(#41): ConfigUseCase を可変 store + reload() 化し不正時は前回値保持"`

---

## Task C: ConfigWatchGateway — Domain 契約

**Files:**

- Create: `Sources/Domain/Misc/ConfigWatchGateway.swift`

`ProcessGateway.swift` の定型（protocol + `…Key: TestDependencyKey` + `DependencyValues` 拡張 + `Unimplemented…`）に厳密に合わせる。

- [ ] **Step 1: 実装（Domain は coverage 除外なので契約のみ・別途テスト不要）**

```swift
// Sources/Domain/Misc/ConfigWatchGateway.swift
import Dependencies

/// 停止可能な監視ハンドル。
public protocol ConfigWatchToken: Sendable {
    func stop()
}

/// config ディレクトリを監視し、変更のたびに `onChange` を呼ぶ OS 境界。
/// 実体は DispatchSource（fake 注入でテスト可能、AudioTapGateway と同じ正当化）。
public protocol ConfigWatchGateway: Sendable {
    /// `directory` を監視開始。イベント毎に `onChange` を任意キューで呼ぶ。
    /// 監視を張れない場合は nil。
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?
}

public enum ConfigWatchGatewayKey: TestDependencyKey {
    public static let testValue: any ConfigWatchGateway = UnimplementedConfigWatchGateway()
}

extension DependencyValues {
    public var configWatchGateway: any ConfigWatchGateway {
        get { self[ConfigWatchGatewayKey.self] }
        set { self[ConfigWatchGatewayKey.self] = newValue }
    }
}

private struct UnimplementedConfigWatchGateway: ConfigWatchGateway {
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? { nil }
}
```

- [ ] **Step 2: ビルド確認** — Run: `swift build` / Expected: 成功
- [ ] **Step 3: commit** — `git add -A && git commit -m "feat(#41): ConfigWatchGateway 契約を Domain に追加"`

---

## Task D: FileWatchGateway — ライブ実装（DispatchSource dir 監視）

**Files:**

- Create: `Sources/FileWatchGateway/FileWatchGateway.swift`
- Create: `Tests/FileWatchGatewayTests/FileWatchGatewayTests.swift`
- Modify: `Package.swift`（`.target(name: "FileWatchGateway", dependencies: ["Domain"])` と `.testTarget(name: "FileWatchGatewayTests", dependencies: ["FileWatchGateway", "Domain"])`。既存 `DarwinGateway` target の書式に合わせる）

親ディレクトリを `O_EVTONLY` で開き `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:[.write,.delete,.rename], queue:)`。atomic-save（rename）でファイル fd は失効するが**ディレクトリ**監視なので生き残る。token が `cancel()` + `close(fd)`。

- [ ] **Step 1: 失敗するテストを書く**（実 FS を使う結合テスト。temp dir を作りファイルを書き、`onChange` が発火することを polling で確認）

```swift
// Tests/FileWatchGatewayTests/FileWatchGatewayTests.swift
import Foundation
import Testing
@testable import FileWatchGateway

@Suite("FileWatchGateway")
struct FileWatchGatewayTests {
    @Test("ディレクトリ内のファイル書込で onChange が発火する")
    func firesOnWrite() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lyra-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let box = FiredBox()
        let token = FileWatchGateway().watch(directory: dir.path) { box.fire() }
        #expect(token != nil)
        defer { token?.stop() }

        // イベントが確実に届くよう少し待ってから書込
        try await Task.sleep(for: .milliseconds(50))
        try "hello".write(to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let deadline = ContinuousClock.now + .seconds(3)
        while !box.fired, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(box.fired)
    }
}

final class FiredBox: @unchecked Sendable {
    private let lock = NSLock(); private var _fired = false
    var fired: Bool { lock.withLock { _fired } }
    func fire() { lock.withLock { _fired = true } }
}
```

- [ ] **Step 2: 失敗を確認** — Run: `swift test --filter FileWatchGatewayTests` / Expected: FAIL（型未定義）

- [ ] **Step 3: 実装**

```swift
// Sources/FileWatchGateway/FileWatchGateway.swift
import Darwin
import Dispatch
import Domain

public struct FileWatchGateway: Sendable {
    public init() {}
}

extension FileWatchGateway: ConfigWatchGateway {
    public func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .global())
        source.setEventHandler { onChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return FileWatchToken(source: source)
    }
}

private final class FileWatchToken: ConfigWatchToken, @unchecked Sendable {
    private let source: any DispatchSourceFileSystemObject
    init(source: any DispatchSourceFileSystemObject) { self.source = source }
    func stop() { source.cancel() }
}
```

- [ ] **Step 4: 成功を確認** — Run: `swift test --filter FileWatchGatewayTests` / Expected: PASS
- [ ] **Step 5: commit** — `git add -A && git commit -m "feat(#41): FileWatchGateway（DispatchSource ディレクトリ監視）を追加"`

---

## Task E: ConfigInteractor — 契約 + ライブ実装（監視駆動・debounce・reload）

**Files:**

- Create: `Sources/Domain/Interactor/ConfigInteractor.swift`
- Create: `Sources/ConfigInteractor/ConfigInteractorImpl.swift`
- Create: `Tests/ConfigInteractorTests/ConfigInteractorImplTests.swift`
- Modify: `Package.swift`（`.target(name: "ConfigInteractor", dependencies: ["Domain"])` + testTarget。`ScreenInteractor` target 書式に合わせる）

`ScreenInteractor` の「Interactor + AnyPublisher」形。監視イベントは `@Dependency(\.continuousClock)` で debounce（`AppPresenter` の Task+clock パターン、テストは `ImmediateClock`）。`appStyleChanges` は ping（PassthroughSubject）、`invalidConfig` は最新保持（CurrentValueSubject、`nil`=正常）。

- [ ] **Step 1: 契約を書く**

```swift
// Sources/Domain/Interactor/ConfigInteractor.swift
import Combine
import Dependencies

public protocol ConfigInteractor: Sendable {
    /// reload が新しい AppStyle を適用した時に発火する Void ping。
    var appStyleChanges: AnyPublisher<Void, Never> { get }
    /// 現在の不正状態（nil=正常、非nil=前回値保持中）。最新値を replay。
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { get }
    func start()
    func stop()
}

public enum ConfigInteractorKey: TestDependencyKey {
    public static let testValue: any ConfigInteractor = UnimplementedConfigInteractor()
}

extension DependencyValues {
    public var configInteractor: any ConfigInteractor {
        get { self[ConfigInteractorKey.self] }
        set { self[ConfigInteractorKey.self] = newValue }
    }
}

private struct UnimplementedConfigInteractor: ConfigInteractor {
    var appStyleChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { Just(nil).eraseToAnyPublisher() }
    func start() {}
    func stop() {}
}
```

- [ ] **Step 2: 失敗するテストを書く**（fake gateway で「変更」を号令一下発火、fake config useCase の reload 結果を制御）

```swift
// Tests/ConfigInteractorTests/ConfigInteractorImplTests.swift
import Combine
import Dependencies
import Domain
import Testing
@testable import ConfigInteractor

@Suite("ConfigInteractorImpl")
struct ConfigInteractorImplTests {
    @Test(".updated で appStyleChanges が発火し invalidConfig が nil になる")
    func firesPingOnUpdate() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: { ConfigInteractorImpl() }

        var pinged = false
        var lastInvalid: ConfigReloadFailure?? = nil
        let c1 = interactor.appStyleChanges.sink { pinged = true }
        let c2 = interactor.invalidConfig.sink { lastInvalid = $0 }
        interactor.start()
        gateway.fire()                       // 監視イベント発火

        let deadline = ContinuousClock.now + .seconds(2)
        while !pinged, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(pinged)
        #expect((lastInvalid ?? nil) == nil)
        _ = (c1, c2); interactor.stop()
    }

    @Test(".invalid で invalidConfig に failure が流れ ping は出ない")
    func surfacesFailureOnInvalid() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .invalid(.init(path: "/c.toml", reason: .decode("bad"))))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: { ConfigInteractorImpl() }

        var invalid: ConfigReloadFailure?
        let c = interactor.invalidConfig.sink { invalid = $0 }
        interactor.start(); gateway.fire()

        let deadline = ContinuousClock.now + .seconds(2)
        while invalid == nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(invalid?.reason == .decode("bad"))
        _ = c; interactor.stop()
    }
}

// fake gateway: watch() で onChange を保持し fire() で発火
final class FakeConfigWatchGateway: ConfigWatchGateway, @unchecked Sendable {
    private let lock = NSLock(); private var handler: (@Sendable () -> Void)?
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock { handler = onChange }; return FakeToken()
    }
    func fire() { lock.withLock { handler }?() }
}
struct FakeToken: ConfigWatchToken { func stop() {} }

final class StubConfigUseCase: ConfigUseCase, @unchecked Sendable {
    let outcome: ConfigReloadOutcome
    init(outcome: ConfigReloadOutcome) { self.outcome = outcome }
    var appStyle: AppStyle { .init() }
    func reload() -> ConfigReloadOutcome { outcome }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { "/tmp/config.toml" }   // watch dir 解決に非nilが要る
}
```

- [ ] **Step 3: 失敗を確認** — Run: `swift test --filter ConfigInteractorImplTests` / Expected: FAIL

- [ ] **Step 4: 実装**

```swift
// Sources/ConfigInteractor/ConfigInteractorImpl.swift
import Combine
import Dependencies
import Domain
import Foundation

public final class ConfigInteractorImpl: @unchecked Sendable {
    @Dependency(\.configWatchGateway) private var gateway
    @Dependency(\.configUseCase) private var configUseCase
    @Dependency(\.continuousClock) private var clock

    private let appStyleSubject = PassthroughSubject<Void, Never>()
    private let invalidSubject = CurrentValueSubject<ConfigReloadFailure?, Never>(nil)
    private let lock = NSLock()
    private var token: (any ConfigWatchToken)?
    private var debounceTask: Task<Void, Never>?

    public init() {}
}

extension ConfigInteractorImpl: ConfigInteractor {
    public var appStyleChanges: AnyPublisher<Void, Never> { appStyleSubject.eraseToAnyPublisher() }
    public var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { invalidSubject.eraseToAnyPublisher() }

    public func start() {
        // config ファイルが在るときだけ、その親ディレクトリを監視。
        guard let path = configUseCase.existingConfigPath else { return }
        let directory = (path as NSString).deletingLastPathComponent
        lock.withLock {
            token = gateway.watch(directory: directory) { [weak self] in self?.scheduleReload() }
        }
    }

    public func stop() {
        lock.withLock {
            token?.stop(); token = nil
            debounceTask?.cancel(); debounceTask = nil
        }
    }

    // 監視イベントを debounce（連続イベント・巨大書込を coalesce）してから reload。
    private func scheduleReload() {
        lock.withLock {
            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                guard let self else { return }
                try? await clock.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self.applyReload()
            }
        }
    }

    private func applyReload() {
        switch configUseCase.reload() {
        case .updated:
            invalidSubject.send(nil)
            appStyleSubject.send(())
        case .invalid(let failure):
            invalidSubject.send(failure)
        }
    }

    deinit { token?.stop(); debounceTask?.cancel() }
}
```

- [ ] **Step 5: 成功を確認** — Run: `swift test --filter ConfigInteractorImplTests` / Expected: PASS
- [ ] **Step 6: commit** — `git add -A && git commit -m "feat(#41): ConfigInteractor（監視駆動 debounce reload・変更/不正の配信）を追加"`

---

## Task F: DI 登録

**Files:**

- Modify: `Sources/DependencyInjection/GatewayRegistration.swift`
- Modify: `Sources/DependencyInjection/InteractorRegistration.swift`
- Modify: `Package.swift`（`DependencyInjection` target の依存に `FileWatchGateway`, `ConfigInteractor` を追加）

- [ ] **Step 1: 実装**

```swift
// GatewayRegistration.swift に追加（import FileWatchGateway も）
extension ConfigWatchGatewayKey: DependencyKey {
    public static let liveValue: any ConfigWatchGateway = FileWatchGateway()
}
```

```swift
// InteractorRegistration.swift に追加（import ConfigInteractor も）
extension ConfigInteractorKey: DependencyKey {
    public static let liveValue: any ConfigInteractor = ConfigInteractorImpl()
}
```

- [ ] **Step 2: ビルド確認** — Run: `swift build` / Expected: 成功
- [ ] **Step 3: commit** — `git add -A && git commit -m "feat(#41): ConfigWatchGateway/ConfigInteractor の liveValue を登録"`

---

## Task G: lyrics DataSource の凍結解除（毎回読み）

**Files:**

- Modify: `Sources/LyricsDataSource/CustomScriptLyricsDataSourceImpl.swift`
- Modify/Add: `Tests/LyricsDataSourceTests/…`（既存の該当テストを確認し、`fallback_command` 変更が次回 `get()` に反映されることを temp config で検証）

`LLMMetadataDataSourceImpl.resolve()` と同じく、`init()` で `let` 固定していた `fallbackCommand`/`timeoutMs`/`configDir` を `get()` 内で毎回 `configDataSource.load()?.config.lyrics` から読むよう変更。`processRunner` テストシームは維持。

- [ ] **Step 1: 現行実装を Read**（`Sources/LyricsDataSource/CustomScriptLyricsDataSourceImpl.swift` 全体）。init 焼付フィールドと `get()` の使用箇所を特定。
- [ ] **Step 2: 失敗するテストを書く** — temp config dir に `[lyrics] fallback_command=[...]` を書き、`ConfigDataSourceImpl(configHome:)` 注入で DataSource 構築 → config を書き換え → 次の `get()` が新 argv を使うことを `processRunner` スパイで確認。
- [ ] **Step 3: 失敗を確認** — Run: `swift test --filter LyricsDataSource`
- [ ] **Step 4: 実装** — 焼付を除去し `get()` 内で都度読み。`$LYRA_CONFIG_DIR`/`$LYRA_CACHE_DIR` 展開・timeout clamp などの既存正規化は維持。
- [ ] **Step 5: 成功を確認** — Run: `swift test --filter LyricsDataSource` / Expected: PASS
- [ ] **Step 6: commit** — `git add -A && git commit -m "fix(#41): lyrics fallback_command を呼出毎に再読込しホットリロード対応"`

---

## Task H: ConfigStatusPresenter — 不正状態を @Published 化

**Files:**

- Create: `Sources/Presenters/Config/ConfigStatusPresenter.swift`
- Create: `Tests/PresentersTests/ConfigStatusPresenterTests.swift`
- Modify: `Package.swift`（`Presenters` target 依存に `ConfigInteractor` は不要 — `@Dependency(\.configInteractor)` は Domain 経由。`Presenters` は既に `Domain` 依存）

`WallpaperPresenter` の ObservableObject + @Published + start/stop + cancellables パターン。`configInteractor.invalidConfig` を購読し `@Published var invalidConfig: ConfigReloadFailure?` に反映。

- [ ] **Step 1: 失敗するテストを書く**

```swift
// Tests/PresentersTests/ConfigStatusPresenterTests.swift
import Combine
import Dependencies
import Domain
import Testing
@testable import Presenters

@MainActor
@Suite("ConfigStatusPresenter")
struct ConfigStatusPresenterTests {
    @Test("invalidConfig 発火で @Published が更新される")
    func reflectsInvalid() async {
        let subject = CurrentValueSubject<ConfigReloadFailure?, Never>(nil)
        let presenter = withDependencies {
            $0.configInteractor = StubConfigInteractor(invalid: subject.eraseToAnyPublisher())
        } operation: { ConfigStatusPresenter() }
        presenter.start(); defer { presenter.stop() }

        subject.send(.init(path: "/c.toml", reason: .unreadable))
        let deadline = ContinuousClock.now + .seconds(2)
        while presenter.invalidConfig == nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(presenter.invalidConfig?.reason == .unreadable)

        subject.send(nil)
        while presenter.invalidConfig != nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(presenter.invalidConfig == nil)
    }
}

final class StubConfigInteractor: ConfigInteractor, @unchecked Sendable {
    let invalid: AnyPublisher<ConfigReloadFailure?, Never>
    init(invalid: AnyPublisher<ConfigReloadFailure?, Never>) { self.invalid = invalid }
    var appStyleChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { invalid }
    func start() {}; func stop() {}
}
```

- [ ] **Step 2: 失敗を確認** — Run: `swift test --filter ConfigStatusPresenter`
- [ ] **Step 3: 実装**

```swift
// Sources/Presenters/Config/ConfigStatusPresenter.swift
import Combine
import Dependencies
import Domain

@MainActor
public final class ConfigStatusPresenter: ObservableObject {
    @Dependency(\.configInteractor) private var interactor
    @Published public private(set) var invalidConfig: ConfigReloadFailure?
    private var cancellables: Set<AnyCancellable> = []
    public init() {}

    public func start() {
        interactor.invalidConfig
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.invalidConfig = $0 }
            .store(in: &cancellables)
    }

    public func stop() { cancellables.removeAll() }
}
```

- [ ] **Step 4: 成功を確認** — Run: `swift test --filter ConfigStatusPresenter` / Expected: PASS
- [ ] **Step 5: commit** — `git add -A && git commit -m "feat(#41): ConfigStatusPresenter で不正状態を @Published 露出"`

---

## Task I: ConfigStatusOverlay — 崩れた測地線球体

**Files:**

- Create: `Sources/Views/Overlay/ConfigStatusOverlay.swift`
- Modify: `Sources/Views/Overlay/OverlayContentView.swift`（`init` に `configStatusPresenter` を追加し ZStack に `ConfigStatusOverlay` を挿入。既存の `WallpaperLoadingOverlay` と同じ条件付き挿入方式）
- Modify: `Tests/ViewsTests/ViewRenderingTests.swift`（不正時に球体が描画される・正常時は空、を `render()` で確認）

`GeodesicLoadingIndicator`（`OverlayContentView.swift:98-194`）を土台に、**琥珀色**＋**支柱破断**の派生を作る。`GeodesicGeometry.edges` を共用。`presenter.invalidConfig != nil` の時だけ条件付き挿入（#252）。**サイズは小さめ・`bottom-trailing` 寄せ**。破断表現は edge の一部を確率的に間引く/オフセット（`GeodesicGeometry` の edge index を種にした決定論的間引き）。

- [ ] **Step 1: 現行 `OverlayContentView.swift` の球体実装を Read**（`GeodesicLoadingIndicator`/`GeodesicMetrics`/`GeodesicGold`/`WallpaperLoadingOverlay`）。破断は「edge index が閾値未満の本数だけ描画をずらす/落とす」で決定論的に。
- [ ] **Step 2: 失敗するテストを書く**（`render()` で `ConfigStatusOverlay(presenter:)` を不正状態・正常状態それぞれで描画しクラッシュしないこと + presenter 状態を assert）

```swift
// Tests/ViewsTests/ViewRenderingTests.swift に Suite 追加
@MainActor
@Suite("ConfigStatusOverlay rendering")
struct ConfigStatusOverlayRenderingTests {
    @Test("invalid 状態で球体が描画される")
    func rendersWhenInvalid() async {
        let subject = CurrentValueSubject<ConfigReloadFailure?, Never>(.init(path: "/c.toml", reason: .decode("x")))
        let presenter = withDependencies {
            $0.configInteractor = StubConfigInteractor(invalid: subject.eraseToAnyPublisher())
        } operation: { ConfigStatusPresenter() }
        presenter.start(); defer { presenter.stop() }
        await waitUntil { presenter.invalidConfig != nil }
        render(ConfigStatusOverlay(presenter: presenter), size: CGSize(width: 800, height: 500))
        #expect(presenter.invalidConfig != nil)
    }

    @Test("正常時は空を描画（クラッシュしない）")
    func rendersEmptyWhenValid() {
        let presenter = withDependencies {
            $0.configInteractor = StubConfigInteractor(invalid: Just(nil).eraseToAnyPublisher())
        } operation: { ConfigStatusPresenter() }
        render(ConfigStatusOverlay(presenter: presenter), size: CGSize(width: 800, height: 500))
    }
}
// StubConfigInteractor は ViewsTests 内にも用意（PresentersTests と重複可、private）
```

- [ ] **Step 3: 失敗を確認** — Run: `swift test --filter ConfigStatusOverlay`
- [ ] **Step 4: 実装** — `ConfigStatusOverlay`（`@ObservedObject presenter`、`if presenter.invalidConfig != nil` で `DestabilizedGeodesicIndicator` + キャプション `config invalid · kept previous style` を `bottom-trailing`・小サイズで挿入、`.transition(.scale.combined(with:.opacity))`）。`DestabilizedGeodesicIndicator` は `GeodesicLoadingIndicator` を琥珀化＋破断化した派生。`OverlayContentView` に `configStatusPresenter` 引数を追加し ZStack 末尾へ。**#Preview を追加**（明/暗背景でエラー球体を確認）。
- [ ] **Step 5: 成功を確認** — Run: `swift test --filter "ConfigStatusOverlay"` かつ `swift test --filter ViewsTests` / Expected: PASS
- [ ] **Step 6: commit** — `git add -A && git commit -m "feat(#41): 崩れた測地線球体で config 不正をグラフィカル通知"`

> **視覚の詰めは実装後に別途**: 琥珀の色値・サイズ・隅位置・破断度合いは #Preview と dev-verification 実機で調整（spec §7）。この Task では「不正時に琥珀の崩れた球体が出る」動作の成立までを担保。

---

## Task J: AppRouter 配線

**Files:**

- Modify: `Sources/AppRouter/AppRouter.swift`
- Modify: `Tests/AppRouterTests/…`（該当あれば start/stop で ConfigInteractor.start/stop が呼ばれることを fake で確認）

- [ ] **Step 1: 現行 `AppRouter.swift` の `start()`/`stop()` と `OverlayContentView` 生成箇所を Read**。
- [ ] **Step 2: 実装** — `AppRouter` に `@Dependency(\.configInteractor)` と `ConfigStatusPresenter` を持たせ、`start()` で `configInteractor.start()` + `configStatusPresenter.start()`、`stop()` で対の stop。`OverlayContentView(... configStatusPresenter:)` へ注入。
- [ ] **Step 3: ビルド＆既存 AppRouter テスト緑** — Run: `swift build && swift test --filter AppRouterTests`
- [ ] **Step 4: commit** — `git add -A && git commit -m "feat(#41): AppRouter で ConfigInteractor/ConfigStatusPresenter を起動・配線"`

---

## Task K: パイプライン E2E（レーン①）

**Files:**

- Create: `Tests/ConfigInteractorTests/ConfigHotReloadE2ETests.swift`（実 `ConfigUseCaseImpl` + 実 `ConfigInteractorImpl` + fake gateway + `ConfigDataSourceImpl(configHome: temp)` を実 `ConfigRepositoryImpl` に噛ませ、temp config を書き換えて伝播を assert）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// 実グラフを組む: configDataSource を temp に向け、repository/useCase/interactor は実物、gateway だけ fake。
@Test("config を書換え→監視発火→reload で appStyle が新値になり ping が飛ぶ")
func endToEndStyleReload() async throws {
    let dir = /* temp config dir を作り config.toml(A) を書く */
    let gateway = FakeConfigWatchGateway()
    try await withDependencies {
        $0.configDataSource = ConfigDataSourceImpl(configHome: dir.path)
        $0.configRepository = ConfigRepositoryImpl()
        $0.configUseCase = ConfigUseCaseImpl()
        $0.configWatchGateway = gateway
        $0.continuousClock = ImmediateClock()
    } operation: {
        @Dependency(\.configUseCase) var useCase
        let interactor = ConfigInteractorImpl()
        var pinged = false
        let c = interactor.appStyleChanges.sink { pinged = true }
        interactor.start()

        // config.toml を B（別の可視値。例: wallpaper location）に書き換え→発火
        /* write config.toml(B) */
        gateway.fire()
        /* poll until pinged */
        #expect(pinged)
        #expect(useCase.appStyle.wallpaper?.items.first?.location == /* B の値 */)
        _ = c; interactor.stop()
    }
}

@Test("不正 config へ書換え→前回値保持＋invalidConfig 発火")
func endToEndKeepsPreviousOnInvalid() async throws {
    /* A(正常)で起動→B(壊れた toml)へ書換→fire→appStyle は A のまま、invalidConfig 非nil */
}
```

- [ ] **Step 2: 失敗を確認 → 実装は既存タスクで満たされるはず。緑化** — Run: `swift test --filter ConfigHotReloadE2E`
- [ ] **Step 3: commit** — `git add -A && git commit -m "test(#41): config ホットリロードのパイプライン E2E を追加"`

---

## Task L: ドキュメント更新 + 全体テスト + PR

**Files:**

- Modify: `CLAUDE.md`（Key Design Decisions / モジュール依存グラフ / Layer Summary に config hot-reload を追記）
- Modify: `AGENTS.md`（該当あれば）
- Modify: `README.md`（config 変更が再起動不要になった旨・不正時の球体表示を Usage/Configuration に）
- Modify: `Sources/VersionHandler/Resources/version.txt`（feat → minor bump）

- [ ] **Step 1: `module-checklist.md` に従い CLAUDE.md/AGENTS.md/README を更新**（新モジュール `FileWatchGateway`/`ConfigInteractor`、新 Gateway、Key Design Decisions に「push 回避・start/applyStyle・reactive core」）。
- [ ] **Step 2: version.txt を minor bump**（現行値を確認して +1 minor）。
- [ ] **Step 3: 全テスト＆lint** — Run: `swift test && make lint` / Expected: 全緑・フォーマット済み。
- [ ] **Step 4: commit** — `git add -A && git commit -m "docs(#41): config ホットリロード中核をドキュメントに反映 + version bump"`
- [ ] **Step 5: push + PR** — `git push -u origin feat/41-config-hot-reload` → `gh pr create --assignee @me`（draft ではなく通常 PR、本文に spec 参照・ハザード対応表・4レーンテスト方針、`Part of #41`）。

---

## Self-Review 結果（spec との照合）

- **spec §4 中核（store+reload+keep-previous）** → Task A,B ✅
- **spec §5 ConfigWatchGateway** → Task C,D ✅ ／ **ConfigInteractor** → Task E ✅ ／ **DI** → Task F ✅
- **spec §5 lyrics 毎回読み** → Task G ✅
- **spec §7 崩れた球体エラー UX** → Task H,I ✅（視覚の詰めは別途明記）
- **spec §9 検証/keep-previous・missing vs unreadable** → Task B（既存 API 合成で ConfigDataSource 非変更）✅
- **spec §10 親ディレクトリ監視・atomic-save・debounce** → Task D（dir 監視）,E（debounce）✅。**includes 別ディレクトリ**は spec §13 の将来課題として未対応（同ディレクトリ前提）。
- **spec §11 テスト①パイプライン E2E** → Task K ✅ ／ **②レンダ差分** → Task I（球体描画）で一部・Header/Lyrics のレンダ差分は PR2 ／ **③check-overlay** → PR4 ／ **④手動** → 各 PR。
- **spec §12 配信** → 本計画は PR1。PR2-4 は本 PR マージ後に別計画。

**未解決（実装中に確定）**: 球体の視覚パラメータ（色/サイズ/位置/破断度）、debounce 値（150ms 仮）、watch dir 解決（config 不在時の初回作成は本 PR 対象外）。

**型整合チェック**: `ConfigReloadOutcome`/`ConfigReloadFailure`/`ConfigReloadFailure.Reason` は Task A で定義し B/E/H/I で一貫使用。`ConfigWatchGateway.watch(directory:onChange:)`/`ConfigWatchToken.stop()` は C で定義し D/E で一貫。`ConfigInteractor.appStyleChanges`/`invalidConfig`/`start`/`stop` は E で定義し H/J で一貫。
