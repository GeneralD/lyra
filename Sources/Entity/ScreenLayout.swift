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

import CoreGraphics

public struct ScreenLayout {
    public let windowFrame: CGRect
    public let hostingFrame: CGRect
    public let screenOrigin: CGPoint

    public init(windowFrame: CGRect = .zero, hostingFrame: CGRect = .zero, screenOrigin: CGPoint = .zero) {
        self.windowFrame = windowFrame
        self.hostingFrame = hostingFrame
        self.screenOrigin = screenOrigin
    }
}

extension ScreenLayout: Sendable {}