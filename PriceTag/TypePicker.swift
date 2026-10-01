//
//  TypePicker.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

struct TypePicker: View {
    let pick: (SignType) -> Void

    private func describe(_ type: SignType) -> String {
        switch type {
        case .regular:   return "Name, colour, size and one price."
        case .sale:      return "Struck regular price beside the new one."
        case .clearance: return "Percent-off flash, was price, now price."
        case .used:      return "Part number, FITS list, optional pre-owned flag."
        case .apparel:   return "Size run and feature logos to the front."
        }
    }

    private func tone(_ type: SignType) -> Color {
        switch type {
        case .clearance: return Color(hex: 0x4E9A18)
        case .sale:      return Color(hex: 0xE00000)
        case .used:      return Color(hex: 0x215E99)
        default:         return Color.white.opacity(0.7)
        }
    }

    var body: some View {
        ZStack {
            Color.ptCard.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 16)

                    Text("New sign")
                        .font(pt(20, .bold))
                        .foregroundColor(.white)

                    Text("Pick a type — the editor only shows the fields it needs.")
                        .font(pt(13))
                        .foregroundColor(.ptDim)
                        .padding(.top, 4)
                        .padding(.bottom, 16)

                    VStack(spacing: 8) {
                        ForEach(SignType.allCases) { type in
                            Button(action: { pick(type) }) {
                                HStack(spacing: 14) {
                                    stripGlyph(tone(type))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(type.title)
                                            .font(pt(15, .semibold))
                                            .foregroundColor(.white)
                                        Text(describe(type))
                                            .font(pt(12))
                                            .foregroundColor(.ptDim)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Text("→")
                                        .font(pt(16))
                                        .foregroundColor(Color.white.opacity(0.25))
                                }
                                .padding(16)
                                .background(Color.ptInset)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private func stripGlyph(_ color: Color) -> some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Rectangle().fill(color).frame(height: 5)
                Rectangle().fill(color.opacity(0.5)).frame(width: 18, height: 2)
            }
            Rectangle().fill(color).frame(width: 9, height: 7)
        }
        .padding(4)
        .frame(width: 38, height: 26)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(color, lineWidth: 1.5)
        )
    }
}
