//
//  PageComposer.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

//
//  PageComposer.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

struct PageComposer: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var page: SignPage

    @State private var pickingType = false
    @State private var editing: UUID? = nil
    @State private var pdfURL: URL? = nil
    @State private var showShare = false

    // The body is deliberately thin — SwiftUI's type checker gives up on this view
    // if the whole page is written as one expression.
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ptBG.ignoresSafeArea()
            content
            bottomBar
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $pickingType) { typeSheet }
        .sheet(item: editTarget) { target in
            NavigationStack {
                SignEditor(sign: binding(for: target.id)) { saveToLibrary(target.id) }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = pdfURL { ActivityView(url: url) }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                TextField("", text: $page.title, prompt:
                    Text("Untitled page").foregroundColor(Color.white.opacity(0.3))
                )
                .font(pt(28, .bold))
                .foregroundColor(.white)
                .padding(.top, 14)

                Text("\(page.signs.count) of 4 filled · letter, 0.5in margins")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 6)

                sheetOfSigns

                Text("Tap a sign to edit · long-press to change type · border is the cut line")
                    .font(pt(11))
                    .foregroundColor(Color.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("← Pages")
                    .font(pt(15, .medium))
                    .foregroundColor(.ptAccent)
            }
            Spacer()
            NavigationLink(destination: PrintPreview(page: page)) {
                Text("Preview")
                    .font(pt(15, .medium))
                    .foregroundColor(.ptAccent)
            }
        }
        .padding(.top, 4)
    }

    private var sheetOfSigns: some View {
        VStack(spacing: 7) {
            ForEach(page.signs) { sign in
                signRow(sign)
            }
            if page.signs.count < 4 { addSlot }
        }
        .padding(7)
        .background(Color.white)
        .cornerRadius(8)
        .padding(.top, 22)
    }

    private func signRow(_ sign: Sign) -> some View {
        Button(action: { editing = sign.id }) {
            ScaledSign(sign: sign)
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(sign) }
    }

    @ViewBuilder
    private func rowMenu(_ sign: Sign) -> some View {
        Section("Change type") {
            ForEach(SignType.allCases) { type in
                Button(action: { setType(type, on: sign.id) }) {
                    Label(type.title, systemImage: sign.type == type ? "checkmark" : "")
                }
            }
        }
        Button(role: .destructive, action: { remove(sign.id) }) {
            Label("Delete sign", systemImage: "trash")
        }
    }

    private var addSlot: some View {
        Button(action: { pickingType = true }) {
            Text("+ Add sign")
                .font(pt(13, .medium))
                .foregroundColor(Color.black.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .overlay(
                    Rectangle().strokeBorder(
                        Color.black.opacity(0.2),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            PillButton(title: "Add sign") { pickingType = true }
            PillButton(title: "Export PDF", filled: true) {
                pdfURL = exportPDF(page: page, signs: store.printable(page))
                showShare = pdfURL != nil
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.ptBG.opacity(0), Color.ptBG],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var typeSheet: some View {
        TypePicker { type in
            let fresh = Sign(type: type)
            page.signs.append(fresh)
            pickingType = false
            editing = fresh.id
        }
    }

    // MARK: - Identity, not position

    /// Signs are addressed by id everywhere. Binding the editor to an array index
    /// crashes the moment a sign is deleted or reordered while the sheet is open.
    private var editTarget: Binding<EditTarget?> {
        return Binding(
            get: {
                guard let id = editing, page.signs.contains(where: { $0.id == id }) else {
                    return nil
                }
                return EditTarget(id: id)
            },
            set: { editing = $0?.id }
        )
    }

    private func binding(for id: UUID) -> Binding<Sign> {
        return Binding(
            get: { return page.signs.first(where: { $0.id == id }) ?? Sign() },
            set: { newValue in
                if let i = page.signs.firstIndex(where: { $0.id == id }) {
                    page.signs[i] = newValue
                }
            }
        )
    }

    private func saveToLibrary(_ id: UUID) {
        if let sign = page.signs.first(where: { $0.id == id }) {
            store.library.append(sign)
        }
    }

    private func setType(_ type: SignType, on id: UUID) {
        guard let i = page.signs.firstIndex(where: { $0.id == id }) else { return }
        page.signs[i].type = type
    }

    private func remove(_ id: UUID) {
        if editing == id { editing = nil }
        page.signs.removeAll { $0.id == id }
    }
}

struct EditTarget: Identifiable {
    let id: UUID
}
