//
//  OtherTabs.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(pt(34, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                Text("Saved signs. Tap to drop a copy onto the first page with room.")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                VStack(spacing: 14) {
                    ForEach(store.library) { sign in
                        Button(action: { add(sign) }) {
                            VStack(alignment: .leading, spacing: 8) {
                                ScaledSign(sign: sign)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(sign.name.isEmpty ? "Untitled" : sign.name)
                                    .font(pt(13, .semibold))
                                    .foregroundColor(.white)
                                Overline(text: sign.type.title)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.ptBG)
    }

    private func add(_ sign: Sign) {
        guard let index = store.pages.firstIndex(where: { $0.signs.count < 4 }) else { return }
        var copy = sign
        copy.id = UUID()
        store.pages[index].signs.append(copy)
    }
}

struct TemplatesScreen: View {
    @EnvironmentObject var store: Store

    private let presets: [(String, String, SignType)] = [
        ("Helmet clearance", "Percent off, was price, now price, colour and size.", .clearance),
        ("Helmet — regular", "Brand, model, colour, size, single price.", .regular),
        ("Boots & apparel", "Size run with feature logos across the header.", .apparel),
        ("BMW part + fitment", "Part number, split price, model fitment list.", .used),
        ("Pre-owned unit", "Part number and FITS list under a pre-owned flag.", .used),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Templates")
                    .font(pt(34, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                Text("Starting points with the fields already laid out.")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                VStack(spacing: 12) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                        Button(action: { start(preset.2) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(preset.0)
                                        .font(pt(16, .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("USE")
                                        .font(pt(11, .medium))
                                        .kerning(0.9)
                                        .foregroundColor(.ptAccent)
                                }
                                Text(preset.1)
                                    .font(pt(13))
                                    .foregroundColor(Color.white.opacity(0.45))
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ptCard)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.ptHair, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.ptBG)
    }

    private func start(_ type: SignType) {
        if let index = store.pages.firstIndex(where: { $0.signs.count < 4 }) {
            store.pages[index].signs.append(Sign(type: type))
        } else {
            var page = SignPage()
            page.signs = [Sign(type: type)]
            store.pages.append(page)
        }
    }
}
