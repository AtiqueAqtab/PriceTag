//
//  FitmentEditor.swift
//  PriceTag
//
//  The Fitment section of the sign editor: rows of years and models.
//

import SwiftUI

/// Lays views out left to right and wraps them onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > limit {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = proposal.width ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Which model's short name is being edited.
private struct ShortTarget: Identifiable {
    let rowID: UUID
    let modelID: UUID
    var id: UUID { return modelID }
}

struct FitmentEditor: View {
    @EnvironmentObject var store: Store
    @Binding var sign: Sign
    /// True when the sign prints on a landscape page, which has room for more rows of tags.
    var landscape: Bool = false

    /// The row whose model field is open, and what has been typed into it.
    @State private var typingIn: UUID? = nil
    @State private var draft = ""
    @FocusState private var draftFocused: Bool
    @State private var shortTarget: ShortTarget? = nil
    @State private var pasting = false
    @State private var pasteText = ""

    private var rows: [FitmentRow] {
        return sign.fitmentRows ?? []
    }

    private var suggestionPool: [FitmentModel] {
        return fitmentModelSuggestions(from: store.visibleLibrary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Overline(text: "Fitment")
                Spacer()
                Text("One row = these models, these years")
                    .font(pt(11))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .padding(.top, 24)
            .padding(.bottom, 10)

            CardGroup {
                HStack {
                    Text("Fits all models")
                        .font(pt(14))
                        .foregroundColor(Color.white.opacity(0.7))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { return sign.universalFit == true },
                        set: { sign.universalFit = $0 ? true : nil }
                    ))
                    .labelsHidden()
                    .tint(Color.ptAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if sign.universalFit != true {
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        rowCard(row)
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 8) {
                    actionButton("+ Add years") { addRow() }
                    actionButton("Paste a list") {
                        pasteText = ""
                        pasting = true
                    }
                }
                .padding(.top, 10)
            }

            if let warning = warning {
                Text(warning)
                    .font(pt(12))
                    .foregroundColor(Color(hex: 0xF0D36A))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x2A2410))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 10)
            }
        }
        .onAppear {
            // Signs saved with plain fitment lines get one row per line.
            if sign.fitmentRows == nil && !sign.fitment.isEmpty {
                sign.adoptFitmentRows()
            }
        }
        .sheet(item: $shortTarget) { target in
            shortSheet(target)
        }
        .sheet(isPresented: $pasting) {
            pasteSheet
        }
    }

    // MARK: Overflow warning

    private var warning: String? {
        if sign.fitTags.isEmpty { return nil }
        let plan = SignFaceView(sign: sign, landscape: landscape).fitmentPlan
        if plan.hidden > 0 {
            let n = plan.hidden
            return "\(n) \(n == 1 ? "tag doesn't" : "tags don't") fit on the sign and print as “+\(n) more”. Use short names, merge rows with the same years, or "
                + (landscape ? "remove some." : "use a landscape page.")
        }
        if plan.fontSize < 11 {
            return "The type shrinks to \(Int(plan.fontSize)) pt so every tag fits."
        }
        return nil
    }

    // MARK: Rows

    private func rowCard(_ row: FitmentRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("YEARS")
                    .font(pt(10, .semibold))
                    .kerning(1.1)
                    .foregroundColor(Color.white.opacity(0.35))
                ForEach(row.years) { range in
                    yearFields(row.id, range)
                }
                Button(action: { addRange(row.id) }) {
                    Text("+ range")
                        .font(pt(12, .semibold))
                        .foregroundColor(Color.ptAccent)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button(action: { removeRow(row.id) }) {
                    Image(systemName: "xmark")
                        .font(pt(12))
                        .foregroundColor(Color.white.opacity(0.35))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete row")
            }

            WrapLayout(spacing: 6) {
                ForEach(row.models) { model in
                    modelChip(row.id, model)
                }
                if typingIn == row.id {
                    TextField("", text: $draft, prompt:
                        Text("Model").foregroundColor(Color.white.opacity(0.3))
                    )
                    .font(pt(13))
                    .foregroundColor(.white)
                    .focused($draftFocused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit { commitDraft(row.id) }
                    .frame(width: 130)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Color.ptAccent, lineWidth: 1))
                } else {
                    Button(action: { startTyping(row.id) }) {
                        Text("+ model")
                            .font(pt(13, .semibold))
                            .foregroundColor(Color.ptAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if typingIn == row.id {
                suggestionList(row)
            }

            if let tag = row.tag {
                Text("Prints: " + tag.models + (tag.years.isEmpty ? "" : "  " + tag.years))
                    .font(pt(11))
                    .foregroundColor(Color.white.opacity(0.35))
            }
        }
        .padding(12)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(typingIn == row.id ? Color.ptAccent : Color.ptHair, lineWidth: 1)
        )
    }

    private func yearFields(_ rowID: UUID, _ range: YearRange) -> some View {
        HStack(spacing: 4) {
            yearField(rowID, range.id, isFrom: true)
            Text("–")
                .foregroundColor(Color.white.opacity(0.4))
            yearField(rowID, range.id, isFrom: false)
        }
    }

    private func yearField(_ rowID: UUID, _ rangeID: UUID, isFrom: Bool) -> some View {
        let binding = Binding<String>(
            get: {
                guard let row = rows.first(where: { $0.id == rowID }),
                      let range = row.years.first(where: { $0.id == rangeID }) else { return "" }
                let value = isFrom ? range.from : range.to
                return value.map { String($0) } ?? ""
            },
            set: { text in
                let digits = String(text.filter { $0.isNumber }.prefix(4))
                mutate(rowID) { row in
                    guard let k = row.years.firstIndex(where: { $0.id == rangeID }) else { return }
                    if isFrom {
                        row.years[k].from = Int(digits)
                    } else {
                        row.years[k].to = Int(digits)
                    }
                }
            }
        )
        return TextField("", text: binding, prompt:
            Text(isFrom ? "From" : "To").foregroundColor(Color.white.opacity(0.3))
        )
        .font(pt(13))
        .foregroundColor(.white)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .frame(width: 50)
        .padding(.vertical, 7)
        .background(Color.ptInset)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func modelChip(_ rowID: UUID, _ model: FitmentModel) -> some View {
        HStack(spacing: 6) {
            Button(action: { shortTarget = ShortTarget(rowID: rowID, modelID: model.id) }) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(pt(13))
                        .foregroundColor(.white)
                    if let short = model.short, !short.isEmpty {
                        Text(short)
                            .font(pt(11, .medium))
                            .foregroundColor(Color(hex: 0xA5A8FF))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.ptAccent.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            Button(action: { removeModel(rowID, model.id) }) {
                Image(systemName: "xmark")
                    .font(pt(10))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove " + model.name)
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background(Color.ptAccent.opacity(0.15))
        .overlay(Capsule().strokeBorder(Color.ptAccent.opacity(0.7), lineWidth: 1))
        .clipShape(Capsule())
    }

    /// Models from the Library that match what has been typed.
    private func suggestions(for row: FitmentRow) -> [FitmentModel] {
        let typed = draft.trimmingCharacters(in: .whitespaces).lowercased()
        let used = Set(row.models.map { $0.name.lowercased() })
        let pool = suggestionPool.filter { !used.contains($0.name.lowercased()) }
        if typed.isEmpty { return Array(pool.prefix(5)) }
        return Array(pool.filter { $0.name.lowercased().contains(typed) }.prefix(5))
    }

    @ViewBuilder
    private func suggestionList(_ row: FitmentRow) -> some View {
        let list = suggestions(for: row)
        if !list.isEmpty {
            VStack(spacing: 0) {
                ForEach(list) { model in
                    Button(action: { addModel(model, to: row.id) }) {
                        HStack {
                            Text(model.name)
                                .font(pt(14))
                                .foregroundColor(Color.white.opacity(0.85))
                            if let short = model.short, !short.isEmpty {
                                Text(short)
                                    .font(pt(11))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.ptInset)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(pt(14, .semibold))
                .foregroundColor(Color.ptAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.ptInset)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Short name and paste sheets

    private func shortSheet(_ target: ShortTarget) -> some View {
        let model = rows.first(where: { $0.id == target.rowID })?
            .models.first(where: { $0.id == target.modelID })
        let binding = Binding<String>(
            get: { return model?.short ?? "" },
            set: { text in
                mutate(target.rowID) { row in
                    guard let j = row.models.firstIndex(where: { $0.id == target.modelID }) else { return }
                    row.models[j].short = text.isEmpty ? nil : text
                }
            }
        )
        return ZStack {
            Color.ptCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(model?.name ?? "Model")
                    .font(pt(18, .semibold))
                    .foregroundColor(.white)
                Overline(text: "Short name")
                TextField("", text: binding, prompt:
                    Text("e.g. GSA").foregroundColor(Color.white.opacity(0.3))
                )
                .font(pt(16))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color.ptInset)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Used when this model shares a tag with others, so “R 1250 GS / R 1250 GS Adventure” prints as “R 1250 GS / GSA”. Leave it empty to print the full name.")
                    .font(pt(12))
                    .foregroundColor(.ptDim)
                PillButton(title: "Done", filled: true) { shortTarget = nil }
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .presentationDetents([.height(340)])
    }

    private var pasteSheet: some View {
        ZStack {
            Color.ptCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Cancel") { pasting = false }
                        .font(pt(15, .medium))
                        .foregroundColor(.ptAccent)
                    Spacer()
                    Text("Paste a list")
                        .font(pt(16, .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Add") { addPasted() }
                        .font(pt(15, .semibold))
                        .foregroundColor(pasteText.isEmpty ? Color.white.opacity(0.3) : .ptAccent)
                        .disabled(pasteText.isEmpty)
                }
                TextEditor(text: $pasteText)
                    .font(pt(14, .medium))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.ptInset)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(minHeight: 160)
                Text("One line per row, for example “2019-2024 R 1250 GS / R 1250 GS Adventure”. Lines with the same years share a row.")
                    .font(pt(12))
                    .foregroundColor(.ptDim)
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    // MARK: Changes

    /// Changes one row, then keeps the plain-text fitment in step.
    private func mutate(_ id: UUID, _ change: (inout FitmentRow) -> Void) {
        var all = sign.fitmentRows ?? []
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[i])
        sign.fitmentRows = all
        sign.syncFitmentText()
    }

    private func addRow() {
        var all = sign.fitmentRows ?? []
        all.append(FitmentRow())
        sign.fitmentRows = all
        sign.syncFitmentText()
    }

    private func removeRow(_ id: UUID) {
        if typingIn == id { typingIn = nil }
        var all = sign.fitmentRows ?? []
        all.removeAll { $0.id == id }
        sign.fitmentRows = all
        sign.syncFitmentText()
    }

    private func addRange(_ rowID: UUID) {
        mutate(rowID) { $0.years.append(YearRange()) }
    }

    private func removeModel(_ rowID: UUID, _ modelID: UUID) {
        mutate(rowID) { row in row.models.removeAll { $0.id == modelID } }
    }

    private func startTyping(_ rowID: UUID) {
        draft = ""
        typingIn = rowID
        // The field only exists once this change has been drawn.
        DispatchQueue.main.async { draftFocused = true }
    }

    /// Adds what was typed as a model. An empty field closes it.
    private func commitDraft(_ rowID: UUID) {
        let name = draft.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            typingIn = nil
            return
        }
        // A name already in the Library brings its short name along.
        let known = suggestionPool.first { $0.name.lowercased() == name.lowercased() }
        addModel(known ?? FitmentModel(name: name), to: rowID)
    }

    private func addModel(_ model: FitmentModel, to rowID: UUID) {
        var fresh = model
        fresh.id = UUID()
        mutate(rowID) { $0.models.append(fresh) }
        draft = ""
        draftFocused = true
    }

    private func addPasted() {
        let parsed = FitmentParser.rows(from: pasteText)
        var all = sign.fitmentRows ?? []
        all.append(contentsOf: parsed)
        sign.fitmentRows = all
        sign.syncFitmentText()
        pasting = false
    }
}
