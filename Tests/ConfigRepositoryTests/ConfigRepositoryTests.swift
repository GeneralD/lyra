import Dependencies
import Domain
import Foundation
import Testing

@testable import ConfigRepository

@Suite("ConfigRepository")
struct ConfigRepositoryTests {

    @Suite("loadAppStyle")
    struct LoadAppStyle {
        @Test("returns default AppStyle when dataSource returns nil")
        func returnsDefaultWhenNil() {
            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: nil)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                let defaultStyle = AppStyle()
                #expect(style.wallpaper == defaultStyle.wallpaper)
                #expect(style.ai == nil)
                #expect(style.screen == defaultStyle.screen)
            }
        }

        @Test("passes raw wallpaper value and configDir through")
        func wallpaperRawValue() {
            let config = makeAppConfig(wallpaper: "bg.mp4")
            let result = ConfigLoadResult(config: config, configDir: "/Users/test/.config/lyra")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.wallpaper?.items.first?.location == "bg.mp4")
                #expect(style.configDir == "/Users/test/.config/lyra")
            }
        }

        @Test("clamps spectrum bar_width, bar_spacing, and fft_size to sane floors")
        func spectrumClamped() {
            let config = makeAppConfig(
                spectrum: ["bar_width": 0, "bar_spacing": -2, "fft_size": 8])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.spectrum.barWidth == 1)
                #expect(style.spectrum.barSpacing == 0)
                #expect(style.spectrum.fftSize == 64)
            }
        }

        @Test("orders the spectrum band so min_freq stays below max_freq")
        func spectrumFreqOrdered() {
            // An inverted range (min above max) is reordered into a valid
            // ascending band for the analyzer.
            let config = makeAppConfig(spectrum: ["min_freq": 5000, "max_freq": 200])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.spectrum.minFreq < style.spectrum.maxFreq)
                #expect(style.spectrum.minFreq == 200)
            }
        }

        @Test("floors a non-positive spectrum band to a valid ascending range")
        func spectrumFreqNonPositive() {
            // Pathological input (min ≥ max, non-positive) must still yield an
            // ascending band so the analyzer never sees min ≥ max.
            let config = makeAppConfig(spectrum: ["min_freq": -3, "max_freq": 0])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let style = ConfigRepositoryImpl().loadAppStyle()
                #expect(style.spectrum.minFreq >= 1)
                #expect(style.spectrum.minFreq < style.spectrum.maxFreq)
            }
        }

        @Test("clamps spectrum bar_opacity above 1 and floors a negative bar_corner_radius")
        func spectrumOpacityAndCornerClamped() {
            let config = makeAppConfig(spectrum: ["bar_opacity": 1.5, "bar_corner_radius": -4])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let style = ConfigRepositoryImpl().loadAppStyle()
                #expect(style.spectrum.barOpacity == 1)
                #expect(style.spectrum.barCornerRadius == 0)
            }
        }

        @Test("floors a negative spectrum bar_opacity to 0")
        func spectrumOpacityFloored() {
            let config = makeAppConfig(spectrum: ["bar_opacity": -0.5])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                #expect(ConfigRepositoryImpl().loadAppStyle().spectrum.barOpacity == 0)
            }
        }

        @Test("passes valid spectrum bar_opacity and bar_corner_radius straight through")
        func spectrumOpacityAndCornerPassthrough() {
            let config = makeAppConfig(spectrum: ["bar_opacity": 0.4, "bar_corner_radius": 8])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let style = ConfigRepositoryImpl().loadAppStyle()
                #expect(style.spectrum.barOpacity == 0.4)
                #expect(style.spectrum.barCornerRadius == 8)
            }
        }

        @Test("passes wallpaper scale through")
        func wallpaperScale() {
            let config = makeAppConfig(wallpaper: ["location": "bg.mp4", "scale": 1.3])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.wallpaper?.items.first?.location == "bg.mp4")
                #expect(style.wallpaper?.items.first?.scale == 1.3)
            }
        }

        @Test("wallpaper is nil when wallpaper config is nil")
        func wallpaperNil() {
            let config = makeAppConfig(wallpaper: nil)
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.wallpaper == nil)
            }
        }

        @Test("converts AIConfig to AIEndpoint when present")
        func aiConfigPresent() {
            let ai = makeAIConfig(endpoint: "https://api.example.com", model: "gpt-4", apiKey: "sk-test")
            let config = makeAppConfig(ai: ai)
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.ai?.endpoint == "https://api.example.com")
                #expect(style.ai?.model == "gpt-4")
                #expect(style.ai?.apiKey == "sk-test")
            }
        }

        @Test("ai is nil when AIConfig is absent")
        func aiConfigAbsent() {
            let config = makeAppConfig(ai: nil)
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.ai == nil)
            }
        }

        @Test("decode_effect processing_color flows through to DecodeEffect")
        func decodeEffectProcessingColor() {
            let config = makeAppConfig(text: ["decode_effect": ["processing_color": "#FF00FF"]])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.text.decodeEffect.processingColor == .solid("#FF00FFFF"))
            }
        }

        @Test("decode_effect processing_color defaults to green when absent")
        func decodeEffectProcessingColorDefault() {
            let config = makeAppConfig()
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.text.decodeEffect.processingColor == .solid("#4ADE80FF"))
            }
        }

        @Test("ripple shape defaults to circle when [ripple] is absent")
        func rippleShapeDefaultsToCircle() {
            let config = makeAppConfig()
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.ripple.shape == .circle)
            }
        }

        @Test("ripple shape passes polygon spec through to RippleStyle")
        func ripplePolygonShapePassthrough() {
            let config = makeAppConfig(
                ripple: ["shape": ["type": "polygon", "sides": 6, "angle": 15]])
            let result = ConfigLoadResult(config: config, configDir: "/tmp")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.ripple.shape == .polygon(sides: 6, angle: 15))
            }
        }
    }

    @Suite("validate")
    struct Validate {
        @Test("returns .defaults when tryDecode returns empty string")
        func returnsDefaults() {
            withDependencies {
                $0.configDataSource = StubConfigDataSource(tryDecodeResult: .success(""))
            } operation: {
                let repo = ConfigRepositoryImpl()
                let result = repo.validate(strictOptionalSections: true)
                guard case .defaults = result else {
                    Issue.record("Expected .defaults, got \(result)")
                    return
                }
            }
        }

        @Test("returns .loaded when tryDecode returns a path")
        func returnsLoaded() {
            withDependencies {
                $0.configDataSource = StubConfigDataSource(tryDecodeResult: .success("/home/user/.config/lyra/config.toml"))
            } operation: {
                let repo = ConfigRepositoryImpl()
                let result = repo.validate(strictOptionalSections: true)
                guard case .loaded(let path) = result else {
                    Issue.record("Expected .loaded, got \(result)")
                    return
                }
                #expect(path == "/home/user/.config/lyra/config.toml")
            }
        }

        @Test("returns .decodeError when tryDecode throws")
        func returnsDecodeError() {
            withDependencies {
                $0.configDataSource = StubConfigDataSource(tryDecodeResult: .failure(StubError.decodeFailed))
            } operation: {
                let repo = ConfigRepositoryImpl()
                let result = repo.validate(strictOptionalSections: true)
                guard case .decodeError(let path, _) = result else {
                    Issue.record("Expected .decodeError, got \(result)")
                    return
                }
                #expect(path == "config")
            }
        }
    }

    @Suite("healthCheck")
    struct HealthCheck {
        @Test("returns .pass when config is loaded")
        func passWhenLoaded() async {
            await withDependencies {
                $0.configDataSource = StubConfigDataSource(tryDecodeResult: .success("/path/to/config.toml"))
            } operation: {
                let repo = ConfigRepositoryImpl()
                let result = await repo.healthCheck()
                #expect(result.status == .pass)
                #expect(result.detail.contains("loaded"))
            }
        }

        @Test("returns .pass when using defaults")
        func passWhenDefaults() async {
            await withDependencies {
                $0.configDataSource = StubConfigDataSource(tryDecodeResult: .success(""))
            } operation: {
                let repo = ConfigRepositoryImpl()
                let result = await repo.healthCheck()
                #expect(result.status == .pass)
                #expect(result.detail.contains("defaults"))
            }
        }

        @Test("returns .fail when decode error occurs")
        func failWhenDecodeError() async {
            await withDependencies {
                $0.configDataSource = StubConfigDataSource(tryDecodeResult: .failure(StubError.decodeFailed))
            } operation: {
                let repo = ConfigRepositoryImpl()
                let result = await repo.healthCheck()
                #expect(result.status == .fail)
                #expect(result.detail.contains("decode error"))
            }
        }
    }
}

@Suite("delegation")
struct Delegation {
    @Test("template delegates to dataSource")
    func templateDelegates() {
        withDependencies {
            $0.configDataSource = StubConfigDataSource(templateValue: "# toml template")
        } operation: {
            let repo = ConfigRepositoryImpl()
            #expect(repo.template(format: .toml) == "# toml template")
        }
    }

    @Test("template returns nil when dataSource returns nil")
    func templateNil() {
        withDependencies {
            $0.configDataSource = StubConfigDataSource(templateValue: nil)
        } operation: {
            let repo = ConfigRepositoryImpl()
            #expect(repo.template(format: .toml) == nil)
        }
    }

    @Test("writeTemplate delegates to dataSource")
    func writeTemplateDelegates() throws {
        try withDependencies {
            $0.configDataSource = StubConfigDataSource(writeTemplateValue: "/path/config.toml")
        } operation: {
            let repo = ConfigRepositoryImpl()
            let path = try repo.writeTemplate(format: .toml, force: false)
            #expect(path == "/path/config.toml")
        }
    }

    @Test("existingConfigPath delegates to dataSource")
    func existingConfigPathDelegates() {
        withDependencies {
            $0.configDataSource = StubConfigDataSource(configPath: "/home/.config/lyra/config.toml")
        } operation: {
            let repo = ConfigRepositoryImpl()
            #expect(repo.existingConfigPath == "/home/.config/lyra/config.toml")
        }
    }

    @Test("existingConfigPath returns nil when no config exists")
    func existingConfigPathNil() {
        withDependencies {
            $0.configDataSource = StubConfigDataSource()
        } operation: {
            let repo = ConfigRepositoryImpl()
            #expect(repo.existingConfigPath == nil)
        }
    }

    @Test("watchChanges delegates to dataSource and passes onChange through")
    func watchChangesDelegates() {
        let dataSource = WatchRecordingConfigDataSource()
        let token = withDependencies {
            $0.configDataSource = dataSource
        } operation: {
            let repo = ConfigRepositoryImpl()
            return repo.watchChanges { dataSource.onChangeFired.setTrue() }
        }

        #expect(token != nil)
        dataSource.fire()
        #expect(dataSource.onChangeFired.value)
    }
}

// MARK: - Test helpers

private struct StubConfigDataSource: ConfigDataSource {
    var loadResult: ConfigLoadResult?
    var tryDecodeResult: Result<String, Error> = .success("")
    var templateValue: String?
    var writeTemplateValue: String = ""
    var configPath: String?

    func load() -> ConfigLoadResult? { loadResult }

    func tryDecode(strictOptionalSections: Bool) throws -> String {
        try tryDecodeResult.get()
    }

    func template(format: ConfigFormat) -> String? { templateValue }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { writeTemplateValue }
    var existingConfigPath: String? { configPath }
    var configDir: String { "" }
}

/// Records the `watchChanges` subscription so the delegation test can verify the
/// repository passes `onChange` through to its adjacent data source untouched.
private final class WatchRecordingConfigDataSource: ConfigDataSource, @unchecked Sendable {
    let onChangeFired = LockedFlag()
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func fire() {
        lock.withLock { handler }?()
    }

    func load() -> ConfigLoadResult? { nil }
    func tryDecode(strictOptionalSections: Bool) throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
    var configDir: String { "" }

    func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock { handler = onChange }
        return NoopWatchToken()
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func setTrue() {
        lock.withLock { _value = true }
    }
}

private struct NoopWatchToken: ConfigWatchToken {
    func stop() {}
}

private enum StubError: Error, LocalizedError {
    case decodeFailed

    var errorDescription: String? { "stub decode failure" }
}

// MARK: - Test fixtures

private func makeAppConfig(
    wallpaper: Any? = nil,
    ai: AIConfig? = nil,
    ripple: [String: Any]? = nil,
    text: [String: Any]? = nil,
    spectrum: [String: Any]? = nil
) -> AppConfig {
    var fields = [String: Any]()
    wallpaper.map { fields["wallpaper"] = $0 }
    ai.map { fields["ai"] = ["endpoint": $0.endpoint, "model": $0.model, "api_key": $0.apiKey] }
    ripple.map { fields["ripple"] = $0 }
    text.map { fields["text"] = $0 }
    spectrum.map { fields["spectrum"] = $0 }
    let data = try! JSONSerialization.data(withJSONObject: fields)
    return try! JSONDecoder().decode(AppConfig.self, from: data)
}

private func makeAIConfig(
    endpoint: String = "https://api.example.com",
    model: String = "gpt-4",
    apiKey: String = "sk-test"
) -> AIConfig {
    let json = #"{"endpoint":"\#(endpoint)","model":"\#(model)","api_key":"\#(apiKey)"}"#
    return try! JSONDecoder().decode(AIConfig.self, from: json.data(using: .utf8)!)
}
