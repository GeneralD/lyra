// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import ConfigRepository
import Dependencies
import Domain
import LyricsDataSource
import MetadataDataSource
import WallpaperDataSource

extension HealthCheckersKey: DependencyKey {
    public static let liveValue: [any HealthCheckable] = {
        @Dependency(\.configDataSource) var configDataSource

        var checkers: [any HealthCheckable] = [
            ConfigRepositoryImpl(),
            LRCLibAPI.search(query: "test"),
            MusicBrainzAPI.searchRecording(title: "test", artist: nil, duration: nil),
        ]

        if let ai = configDataSource.load()?.config.ai {
            checkers.append(OpenAICompatibleAPI(config: AIEndpoint(endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey)))
        } else {
            checkers.append(SkippedHealthCheck(serviceName: "AI endpoint", reason: "not configured"))
        }

        // YouTube wallpaper tool availability (always check regardless of config)
        checkers.append(contentsOf: WallpaperToolChecker.youtubeCheckers())

        return checkers
    }()
}

private struct SkippedHealthCheck: HealthCheckable {
    let serviceName: String
    let reason: String

    func healthCheck() async -> HealthCheckResult {
        HealthCheckResult(status: .skip, detail: reason)
    }
}