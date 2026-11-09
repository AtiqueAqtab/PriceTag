//
//  PagesScreen.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

/// The list of saved pages, each shown with a thumbnail of its four signs.
struct PagesScreen: View {
    @EnvironmentObject var store: Store
    @State private var choosingStart = false
    @State private var pickingForNewPage = false
    @State private var scanning = false
    /// Select mode: tick pages to export them together. The order ticked is the
    /// order in the PDF.
    @State private var selecting = false
    @State private var selection: [UUID] = []
    @State private var exporting = false
    /// A delete or combine waiting for confirmation, and the pages it covers.
    private enum BulkAction {
        case delete, combine
    }
    @State private var bulk: BulkAction? = nil
    @State private var bulkIDs: [UUID] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Pages")
                            .font(pt(34, .bold))
                            .foregroundColor(.white)
                        Spacer()
                        if !store.pages.isEmpty {
                            Button(selecting ? "Done" : "Select") {
                                selecting.toggle()
                                selection = []
                            }
                            .font(pt(15, .medium))
                            .foregroundColor(.ptAccent)
                            .padding(.trailing, 14)
                        }
                        if !selecting {
                            Button("Scan") { scanning = true }
                                .font(pt(15, .medium))
                                .foregroundColor(.ptAccent)
                                .padding(.trailing, 14)
                            Button("New page") {
                                // With nothing in the Library there is no choice to offer.
                                if store.visibleLibrary.isEmpty && store.signClipboard == nil {
                                    store.pages.append(SignPage())
                                } else {
                                    choosingStart = true
                                }
                            }
                            .font(pt(15, .medium))
                            .foregroundColor(.ptAccent)
                        }
                    }
                    .padding(.top, 8)

                    Text(selecting
                         ? "Tap pages to choose. The number is the order in the PDF."
                         : "Four signs stacked per sheet, letter, narrow margins.")
                        .font(pt(13))
                        .foregroundColor(.ptDim)
                        .padding(.top, 4)
                        .padding(.bottom, 22)

                    LazyVStack(spacing: 14) {
                        ForEach($store.pages) { $page in
                            if selecting {
                                Button(action: { toggle(page.id) }) {
                                    PageCard(page: page, selecting: true,
                                             order: selection.firstIndex(of: page.id).map { $0 + 1 })
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(destination: PageComposer(page: $page)) {
                                    PageCard(page: page)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        bulkIDs = [page.id]
                                        bulk = .delete
                                    }) {
                                        Label("Delete page", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, selecting ? 90 : 30)
            }
            .background(Color.ptBG)
            .navigationBarHidden(true)
            .overlay(alignment: .bottom) {
                if selecting && !selection.isEmpty {
                    selectionBar
                }
            }
            .sheet(isPresented: $exporting) { ExportSheet(pageIDs: selection) }
            .fullScreenCover(isPresented: $scanning) { ScanFlow() }
            .confirmationDialog("New page", isPresented: $choosingStart, titleVisibility: .visible) {
                Button("Blank page") { store.pages.append(SignPage()) }
                if !store.visibleLibrary.isEmpty {
                    Button("Fill from Library") { pickingForNewPage = true }
                }
                if let copied = store.signClipboard {
                    Button("Paste " + (copied.name.isEmpty ? "copied sign" : copied.name)) {
                        var page = SignPage()
                        var sign = copied
                        sign.id = UUID()
                        sign.libraryID = nil
                        sign.landscape = nil
                        page.signs = [sign]
                        store.pages.append(page)
                    }
                }
            }
            .sheet(isPresented: $pickingForNewPage) {
                LibraryPicker(room: 4) { chosen in
                    var page = SignPage()
                    page.signs = chosen
                    store.pages.append(page)
                }
            }
        }
        .confirmationDialog(
            bulkTitle,
            isPresented: Binding(
                get: { bulk != nil },
                set: { if !$0 { bulk = nil } }
            ),
            titleVisibility: .visible
        ) {
            if bulk == .combine {
                Button("Combine") { combine(bulkIDs) }
            } else {
                Button(bulkIDs.count == 1 ? "Delete page" : "Delete \(bulkIDs.count) pages",
                       role: .destructive) { delete(bulkIDs) }
            }
        } message: {
            Text(bulkMessage)
        }
    }
}

extension PagesScreen {
    fileprivate func toggle(_ id: UUID) {
        if let i = selection.firstIndex(of: id) {
            selection.remove(at: i)
        } else {
            selection.append(id)
        }
    }

    /// Delete, combine and export for the pages ticked in select mode.
    fileprivate var selectionBar: some View {
        HStack(spacing: 10) {
            PillButton(title: "Delete") {
                bulkIDs = selection
                bulk = .delete
            }
            if selection.count > 1 {
                PillButton(title: "Combine") {
                    bulkIDs = selection
                    bulk = .combine
                }
            }
            PillButton(title: "Export \(selection.count)", filled: true) { exporting = true }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    fileprivate var bulkTitle: String {
        if bulk == .combine {
            let name = bulkIDs.first.flatMap { id in store.pages.first { $0.id == id }?.title } ?? "the first page"
            return "Combine \(bulkIDs.count) pages into “\(name)”?"
        }
        return bulkIDs.count == 1 ? "Delete this page?" : "Delete \(bulkIDs.count) pages?"
    }

    fileprivate var bulkMessage: String {
        if bulk == .combine {
            return "All their signs go into the first page, in the order ticked. The other pages are removed."
        }
        return "The signs on them are removed too. Signs saved in the Library are not affected."
    }

    fileprivate func delete(_ ids: [UUID]) {
        store.pages.removeAll { ids.contains($0.id) }
        selection.removeAll { ids.contains($0) }
        if store.pages.isEmpty { selecting = false }
    }

    /// Moves every ticked page's signs into the first one, in the order ticked, and
    /// removes the others.
    fileprivate func combine(_ ids: [UUID]) {
        let chosen = ids.compactMap { id in store.pages.first { $0.id == id } }
        guard chosen.count > 1,
              let at = store.pages.firstIndex(where: { $0.id == chosen[0].id }) else { return }
        // Every sign on a page needs an ID of its own, so a repeat gets a fresh one.
        var seen = Set<UUID>()
        var signs: [Sign] = []
        for sign in chosen.flatMap({ $0.signs }) {
            var copy = sign
            if !seen.insert(copy.id).inserted {
                copy.id = UUID()
                seen.insert(copy.id)
            }
            signs.append(copy)
        }
        var merged = chosen[0]
        merged.signs = signs
        store.pages[at] = merged
        let removed = Set(chosen.dropFirst().map { $0.id })
        store.pages.removeAll { removed.contains($0.id) }
        selection = [merged.id]
    }
}

struct PageCard: View {
    let page: SignPage
    /// In select mode the card shows a tick circle, numbered once chosen.
    var selecting = false
    var order: Int? = nil

    private var countText: String {
        let count = page.signs.count
        let landscape = page.sheets.filter { sheetCapacity($0) == 2 }.count
        let kind = landscape > 0 ? " · \(landscape) landscape" : ""
        if count <= 4 && landscape == 0 { return "\(count) of 4 signs" }
        return "\(count) signs · \(page.sheetCount) \(page.sheetCount == 1 ? "sheet" : "sheets")" + kind
    }

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
            .background(alignment: .topLeading) {
                // A second sheet peeking out behind the first.
                if page.sheetCount > 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 74, height: 96)
                        .cornerRadius(4)
                        .offset(x: 6, y: 5)
                }
            }
            .padding(.trailing, page.sheetCount > 1 ? 6 : 0)

            VStack(alignment: .leading, spacing: 5) {
                Text(page.title)
                    .font(pt(17, .semibold))
                    .foregroundColor(.white)
                Text(countText)
                    .font(pt(13))
                    .foregroundColor(.ptDim)
            }

            Spacer()

            if selecting {
                ZStack {
                    Circle()
                        .fill(order == nil ? Color.clear : Color.ptAccent)
                    Circle()
                        .strokeBorder(order == nil ? Color.white.opacity(0.25) : Color.ptAccent, lineWidth: 2)
                    if let order = order {
                        Text("\(order)")
                            .font(pt(13, .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 26, height: 26)
            } else {
                Text("→")
                    .font(pt(18))
                    .foregroundColor(Color.white.opacity(0.3))
            }
        }
        .padding(16)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(order == nil ? Color.ptHair : Color.ptAccent, lineWidth: order == nil ? 1 : 2)
        )
    }
}

/// Picks the pages for an export and the order they print in.
struct PagePickerSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var selection: [UUID]
    @State private var exporting = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ptCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(pt(15, .medium))
                        .foregroundColor(.ptAccent)
                    Spacer()
                    Text("Choose pages")
                        .font(pt(16, .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Cancel").font(pt(15)).hidden()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)
                Text("The number is the order in the PDF.")
                    .font(pt(12))
                    .foregroundColor(.ptDim)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.pages) { page in
                            Button(action: { toggle(page.id) }) {
                                PageCard(page: page, selecting: true,
                                         order: selection.firstIndex(of: page.id).map { $0 + 1 })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 90)
                }
            }
            if !selection.isEmpty {
                PillButton(title: selection.count == 1 ? "Export 1 page…" : "Export \(selection.count) pages…",
                           filled: true) { exporting = true }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $exporting) { ExportSheet(pageIDs: selection) }
    }

    private func toggle(_ id: UUID) {
        if let i = selection.firstIndex(of: id) {
            selection.remove(at: i)
        } else {
            selection.append(id)
        }
    }
}

/// The last step before exporting: what goes in, in what order, and what to do
/// with sheets that are not full.
struct ExportSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let pageIDs: [UUID]

    @AppStorage("exportFill") private var fillRaw = EmptySlots.repeatToFill.rawValue
    @State private var pdfURL: URL? = nil
    @State private var showShare = false
    /// Sheets left out of this export, for each page. Everything starts included.
    @State private var skipped: [UUID: Set<Int>] = [:]

    private var pages: [SignPage] {
        return pageIDs.compactMap { id in store.pages.first { $0.id == id } }
    }

    private var fill: EmptySlots {
        return EmptySlots(rawValue: fillRaw) ?? .repeatToFill
    }

    private var hasPartialSheet: Bool {
        return pages.contains { $0.hasPartialSheet }
    }

    private var explanation: String {
        switch fill {
        case .repeatToFill:
            return "A page's last sheet is completed with copies of its own signs."
        case .blank:
            return "Empty slots stay empty."
        case .pack:
            let packed = printSheets(pages, fill: .pack, skipping: skipped)
            let total = packed.reduce(0) { $0 + $1.compactMap { $0 }.count }
            let sheets = packed.count
            var text = "\(total) signs fill \(sheets) \(sheets == 1 ? "sheet" : "sheets"), in order, with no repeats."
            if skipped.values.contains(where: { !$0.isEmpty }) {
                text += " Skipped sheets are left out first, so the signs after them move up."
            }
            return text
        }
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

    /// Numbered chips for choosing which of a page's sheets to include.
    private func sheetChips(_ page: SignPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Overline(text: "Sheets")
            HStack(spacing: 8) {
                ForEach(0..<page.sheetCount, id: \.self) { index in
                    let included = !(skipped[page.id]?.contains(index) ?? false)
                    Button(action: { toggle(page, index) }) {
                        Text("\(index + 1)")
                            .font(pt(13, .semibold))
                            .foregroundColor(included ? .white : Color.white.opacity(0.4))
                            .strikethrough(!included)
                            .frame(width: 34, height: 30)
                            .background(included ? Color.ptAccent : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(included ? Color.ptAccent : Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 34)
        .padding(.top, 10)
    }

    var body: some View {
        let sheets = printSheets(pages, fill: fill, skipping: skipped)
        return ZStack {
            Color.ptCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(pt(15, .medium))
                        .foregroundColor(.ptAccent)
                    Spacer()
                    Text(pages.count == 1 ? "Export 1 page" : "Export \(pages.count) pages")
                        .font(pt(16, .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Cancel").font(pt(15)).hidden()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(pt(12, .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 22, height: 22)
                                            .background(Color.ptAccent)
                                            .clipShape(Circle())
                                        Text(page.title)
                                            .font(pt(15))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(page.sheetCount > 1
                                             ? "\(page.signs.count) signs · \(page.sheetCount) sheets"
                                             : (page.signs.count == 1 ? "1 sign" : "\(page.signs.count) signs"))
                                            .font(pt(12))
                                            .foregroundColor(.ptDim)
                                    }
                                    if page.sheetCount > 1 {
                                        sheetChips(page)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                if index < pages.count - 1 {
                                    Rectangle().fill(Color.ptHair).frame(height: 1)
                                }
                            }
                        }
                        .background(Color.ptInset)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if hasPartialSheet {
                            FillPicker(raw: $fillRaw,
                                       options: pages.count > 1 ? EmptySlots.allCases : [.repeatToFill, .blank])
                                .padding(.top, 20)
                            Text(explanation)
                                .font(pt(12))
                                .foregroundColor(Color.white.opacity(0.55))
                                .padding(.top, 10)
                        }

                        Text(exportTitle(pages) + ".pdf")
                            .font(pt(12))
                            .foregroundColor(.ptDim)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 26)
                    }
                    .padding(.horizontal, 20)
                }

                PillButton(title: sheets.isEmpty ? "Choose at least one sheet"
                                   : (sheets.count == 1 ? "Export · 1 sheet" : "Export · \(sheets.count) sheets"),
                           filled: true) {
                    guard !sheets.isEmpty else { return }
                    pdfURL = exportPDF(title: exportTitle(pages), sheets: sheets)
                    showShare = pdfURL != nil
                }
                .opacity(sheets.isEmpty ? 0.4 : 1)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = pdfURL { ActivityView(url: url) }
        }
    }
}
