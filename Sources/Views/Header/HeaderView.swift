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

import Domain
import Presenters
import SwiftUI

@MainActor
public struct HeaderView: View {
    @ObservedObject var presenter: HeaderPresenter

    public init(presenter: HeaderPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if presenter.titleState != .idle {
            HStack(spacing: presenter.artworkOpacity > 0 ? 24 : 0) {
                if presenter.artworkOpacity > 0 {
                    if let artworkData = presenter.artworkData, let image = NSImage(data: artworkData) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: presenter.artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .opacity(presenter.artworkOpacity)
                    } else {
                        Color.clear
                            .frame(width: presenter.artworkSize, height: presenter.artworkSize)
                    }
                }
                VStack(alignment: .leading, spacing: presenter.titleStyle.spacing) {
                    Text(presenter.displayTitle)
                        .font(makeFont(style: presenter.titleStyle))
                        .foregroundStyle(presenter.titleStyle.color.shapeStyle)
                        .shadow(color: presenter.titleStyle.shadow.solidColor, radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                    Text(presenter.displayArtist)
                        .font(makeFont(style: presenter.artistStyle))
                        .foregroundStyle(presenter.artistStyle.color.shapeStyle)
                        .shadow(color: presenter.artistStyle.shadow.solidColor, radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }
}

#if DEBUG
    #Preview("Header") {
        HeaderView(presenter: HeaderPresenter())
            .padding()
            .background(.black)
    }
#endif