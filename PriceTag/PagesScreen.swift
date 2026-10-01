//
//  PagesScreen.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

struct PagesScreen: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Pages")
                            .font(pt(34, .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("New page") {
                            store.pages.append(SignPage())
                        }
                        .font(pt(15, .medium))
                        .foregroundColor(.ptAccent)
                    }
                    .padding(.top, 8)

                    Text("Four signs stacked per sheet, letter, narrow margins.")
                        .font(pt(13))
                        .foregroundColor(.ptDim)
                        .padding(.top, 4)
                        .padding(.bottom, 22)

                    VStack(spacing: 14) {
                        ForEach($store.pages) { $page in
                            NavigationLink(destination: PageComposer(page: $page)) {
                                PageCard(page: page)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Color.ptBG)
            .navigationBarHidden(true)
        }
    }
}

struct PageCard: View {
    let page: SignPage

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    HStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 22, height: 3)
                        Spacer()
                        Rectangle()
                            .fill(i < page.signs.count ? Color(hex: 0xE00000) : Color.black.opacity(0.12))
                            .frame(width: 14, height: 4)
                    }
                    .padding(.horizontal, 3)
                    .frame(maxHeight: .infinity)
                    .background(Color(hex: 0xEFEFEC))
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                }
            }
            .padding(3)
            .frame(width: 74, height: 96)
            .background(Color.white)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 5) {
                Text(page.title)
                    .font(pt(17, .semibold))
                    .foregroundColor(.white)
                Text("\(page.signs.count) of 4 signs")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
            }

            Spacer()

            Text("→")
                .font(pt(18))
                .foregroundColor(Color.white.opacity(0.3))
        }
        .padding(16)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.ptHair, lineWidth: 1)
        )
    }
}
