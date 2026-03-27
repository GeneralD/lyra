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

import AppKit
import Dependencies
import Domain

struct AppKitFontMetrics: FontMetricsProvider {
    @MainActor func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double {
        let font = resolveFont(name: fontName, size: fontSize)
        return ceil(font.ascender - font.descender + font.leading) + spacing * 2
    }

    @MainActor private func resolveFont(name: String, size: Double) -> NSFont {
        NSFont(name: name, size: size)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
            ?? .systemFont(ofSize: size)
    }
}

extension FontMetricsProviderKey: DependencyKey {
    public static let liveValue: any FontMetricsProvider = AppKitFontMetrics()
}