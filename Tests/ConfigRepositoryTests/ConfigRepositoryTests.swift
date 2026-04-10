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
            let result = ConfigLoadResult(config: config, configDir: "/Users/test/.config/lyra", path: "/Users/test/.config/lyra/config.toml")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.wallpaper?.location == "bg.mp4")
                #expect(style.configDir == "/Users/test/.config/lyra")
            }
        }

        @Test("wallpaper is nil when wallpaper config is nil")
        func wallpaperNil() {
            let config = makeAppConfig(wallpaper: nil)
            let result = ConfigLoadResult(config: config, configDir: "/tmp", path: "/tmp/config.toml")

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
            let result = ConfigLoadResult(config: config, configDir: "/tmp", path: "/tmp/config.toml")

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
            let result = ConfigLoadResult(config: config, configDir: "/tmp", path: "/tmp/config.toml")

            withDependencies {
                $0.configDataSource = StubConfigDataSource(loadResult: result)
            } operation: {
                let repo = ConfigRepositoryImpl()
                let style = repo.loadAppStyle()
                #expect(style.ai == nil)
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
                let result = repo.validate()
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
                let result = repo.validate()
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
                let result = repo.validate()
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
}

// MARK: - Test helpers

private struct StubConfigDataSource: ConfigDataSource {
    var loadResult: ConfigLoadResult?
    var tryDecodeResult: Result<String, Error> = .success("")
    var templateValue: String?
    var writeTemplateValue: String = ""
    var configPath: String?

    func load() -> ConfigLoadResult? { loadResult }

    func tryDecode() throws -> String {
        try tryDecodeResult.get()
    }

    func template(format: ConfigFormat) -> String? { templateValue }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { writeTemplateValue }
    var existingConfigPath: String? { configPath }
}

private enum StubError: Error, LocalizedError {
    case decodeFailed

    var errorDescription: String? { "stub decode failure" }
}

// MARK: - Test fixtures

private func makeAppConfig(wallpaper: String? = nil, ai: AIConfig? = nil) -> AppConfig {
    var fields = [String: Any]()
    wallpaper.map { fields["wallpaper"] = $0 }
    ai.map { fields["ai"] = ["endpoint": $0.endpoint, "model": $0.model, "api_key": $0.apiKey] }
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
