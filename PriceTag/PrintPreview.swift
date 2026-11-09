//
//  PrintPreview.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

/// Shows every sheet as it will print, with margins, before you share or print it.
struct PrintPreview: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let pages: [SignPage]

    @AppStorage("exportFill") private var fillRaw = EmptySlots.repeatToFill.rawValue
    @State private var pdfURL: URL? = nil
    @State private var showShare = false
    /// Sheets left out of this export, for each page. Everything starts included.
    @State private var skipped: [UUID: Set<Int>] = [:]

    init(page: SignPage) {
        pages = [page]
    }

    init(pages: [SignPage]) {
        self.pages = pages
    }

    private var fill: EmptySlots {
        return EmptySlots(rawValue: fillRaw) ?? .repeatToFill
    }

    private var hasPartialSheet: Bool {
        return pages.contains { $0.hasPartialSheet }
    }

    /// Every sheet of every page, with where it came from.
    private var entries: [(page: SignPage, index: Int, slots: [Sign?])] {
        var out: [(page: SignPage, index: Int, slots: [Sign?])] = []
        for page in pages {
            for (index, chunk) in page.sheets.enumerated() {
                out.append((page: page, index: index, slots: sheetSlots(chunk, fill: fill)))
            }
        }
        return out
    }

    private func isIncluded(_ page: SignPage, _ index: Int) -> Bool {
        return !(skipped[page.id]?.contains(index) ?? false)
    }

    private func toggle(_ page: SignPage, _ index: Int) {
        var set = skipped[page.id] ?? []
        if set.contains(index) {
            set.remove(index)
        } else {
            set.insert(index)
        }
        skipped[page.id] = set
    }

    var body: some View {
        let items = entries
        let sheets = printSheets(pages, fill: fill, skipping: skipped)
        return ZStack(alignment: .bottom) {
            Color.ptBG.ignoresSafeArea()

            ScrollView {
                // Lazy, so a page with many sheets only draws the ones on screen.
                LazyVStack(alignment: .leading, spacing: 0) {
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

                    if items.isEmpty {
                        Text("Nothing to print yet. Add a sign to this page first.")
                            .font(pt(14))
                            .foregroundColor(.ptDim)
                    }

                    ForEach(items.indices, id: \.self) { k in
                        let item = items[k]
                        let included = isIncluded(item.page, item.index)
                        if items.count > 1 {
                            sheetHeader(k, of: items.count, included: included) {
                                toggle(item.page, item.index)
                            }
                        }
                        sheetView(item.slots)
                            .opacity(included ? 1 : 0.28)
                    }

                    if hasPartialSheet {
                        FillPicker(raw: $fillRaw, options: [.repeatToFill, .blank])
                            .padding(.top, 16)
                    }

                    Text(note)
                        .font(pt(12))
                        .foregroundColor(.ptDim)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }

            PillButton(title: shareTitle(printing: sheets.count, of: items.count), filled: true) {
                guard !sheets.isEmpty else { return }
                pdfURL = exportPDF(title: exportTitle(pages), sheets: sheets)
                showShare = pdfURL != nil
            }
            .opacity(sheets.isEmpty && !items.isEmpty ? 0.4 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) {
            if let url = pdfURL { ActivityView(url: url) }
        }
    }

    private func shareTitle(printing: Int, of total: Int) -> String {
        if total <= 1 { return "Share PDF" }
        if printing == 0 { return "Tick a sheet to share" }
        if printing == total { return "Share PDF" }
        return "Share \(printing) of \(total) sheets"
    }

    /// The label above a sheet. With several sheets it carries a tickbox to include or skip it.
    private func sheetHeader(_ index: Int, of total: Int, included: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(included ? Color.ptAccent : Color.clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(included ? Color.ptAccent : Color.white.opacity(0.3), lineWidth: 2)
                    if included {
                        Image(systemName: "checkmark")
                            .font(pt(11, .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 22, height: 22)
                Overline(text: "Sheet \(index + 1) of \(total)")
                Spacer()
                Text(included ? "Included" : "Skipped")
                    .font(pt(12))
                    .foregroundColor(Color.white.opacity(0.35))
            }
            .padding(.top, index == 0 ? 0 : 18)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One printed sheet. An empty slot keeps its space.
    private func sheetView(_ slots: [Sign?]) -> some View {
        let landscape = isLandscapeSheet(slots)
        let pageAspect: CGFloat = landscape ? 11 / 8.5 : 8.5 / 11
        let faceHeight = SignFaceView.printSize.height + (landscape ? SignFaceView.landscapeExtra : 0)
        return GeometryReader { geo in
            let inset = geo.size.width * 0.047
            VStack(spacing: 6) {
                ForEach(slots.indices, id: \.self) { i in
                    if let sign = slots[i] {
                        ScaledSign(sign: sign, landscape: landscape)
                    } else {
                        Color.clear.aspectRatio(
                            SignFaceView.printSize.width / faceHeight,
                            contentMode: .fit
                        )
                    }
                }
            }
            .padding(inset)
            .frame(width: geo.size.width, height: geo.size.width / pageAspect)
            .background(Color.white)
        }
        .aspectRatio(pageAspect, contentMode: .fit)
    }

    private var note: String {
        if hasPartialSheet {
            if fill == .repeatToFill {
                return "The last sheet has empty slots, so they are filled with copies of its own signs. Cut along the borders after laminating."
            }
            return "The last sheet has empty slots, which print blank. Cut along the borders after laminating."
        }
        return "Cut along the borders after laminating."
    }
}

/// A row of choices for what to do with empty slots.
struct FillPicker: View {
    @Binding var raw: String
    let options: [EmptySlots]

    private func isOn(_ option: EmptySlots) -> Bool {
        if raw == option.rawValue { return true }
        // Packing only means something across several pages, so a single page treats it as blank.
        return raw == EmptySlots.pack.rawValue && option == .blank && !options.contains(.pack)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(text: "Sheets that are not full")
            HStack(spacing: 4) {
                ForEach(options) { option in
                    Button(action: { raw = option.rawValue }) {
                        Text(option.title)
                            .font(pt(13, isOn(option) ? .semibold : .medium))
                            .foregroundColor(isOn(option) ? .white : Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isOn(option) ? Color.ptAccent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.ptInset)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
