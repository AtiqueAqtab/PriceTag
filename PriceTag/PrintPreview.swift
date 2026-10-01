//
//  PrintPreview.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

/// Shows the full Letter page with margins before you share or print it.
struct PrintPreview: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let page: SignPage

    @State private var pdfURL: URL? = nil
    @State private var showShare = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ptBG.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("← Page")
                                .font(pt(15, .medium))
                                .foregroundColor(.ptAccent)
                        }
                        Spacer()
                        Overline(text: "Letter · 0.5in margins")
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 14)

                    GeometryReader { geo in
                        let inset = geo.size.width * 0.047
                        VStack(spacing: 6) {
                            ForEach(Array(store.printable(page).enumerated()), id: \.offset) { _, sign in
                                ScaledSign(sign: sign)
                            }
                        }
                        .padding(inset)
                        .frame(width: geo.size.width, height: geo.size.width * 11 / 8.5)
                        .background(Color.white)
                    }
                    .aspectRatio(8.5 / 11, contentMode: .fit)

                    Text(note)
                        .font(pt(12))
                        .foregroundColor(.ptDim)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }

            PillButton(title: "Share PDF", filled: true) {
                pdfURL = exportPDF(page: page, signs: store.printable(page))
                showShare = pdfURL != nil
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) {
            if let url = pdfURL { ActivityView(url: url) }
        }
    }

    private var note: String {
        let filled = page.signs.count
        if filled > 0 && filled < 4 {
            return "Only \(filled) signs on this page, so the empty slots are auto-filled with duplicates. Cut along the borders after laminating."
        }
        return "Cut along the borders after laminating."
    }
}

