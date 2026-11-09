//
//  SignEditor.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

/// Edits one sign, with a live preview above the fields.
///
/// Only the fields used by the sign's type are shown.
struct SignEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @ObservedObject private var logos = LogoLibrary.shared
    @Binding var sign: Sign
    /// True when the sign sits on a landscape page, so the preview shows that layout.
    var landscape: Bool = false
    /// The word after the arrow on the back button.
    var backTitle: String = "Page"
    var saveToLibrary: () -> LibrarySaveResult

    /// Briefly says what the last tap on Save did.
    @State private var saveFlash: String?
    /// A sign already in the Library that looks like this one, found when saving.
    @State private var lookAlike: (match: Sign, others: Int)?
    /// Linked price fields currently holding a value the app suggested, and the exact
    /// text it wrote. A field edited by hand no longer matches, so it stops counting.
    @State private var suggested: [PriceField: String] = [:]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ptBG.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("← " + backTitle)
                                .font(pt(15, .medium))
                                .foregroundColor(.ptAccent)
                        }
                        Spacer()
                        Overline(text: sign.type.title)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                    ScaledSign(sign: sign, landscape: landscape)
                        .padding(16)
                        .background(Color.ptInset)
                        .cornerRadius(12)

                    Text(landscape ? "Live preview · actual print size 10 × 3.67 in" : "Live preview · actual print size 7.5 × 2.375 in")
                        .font(pt(11))
                        .foregroundColor(Color.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    // A landscape page holds Parts signs only, so the type stays put.
                    if !landscape {
                        HStack {
                            Overline(text: "Sign type")
                            Spacer()
                            Text("Switch any time — entries are kept")
                                .font(pt(11))
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                        .padding(.top, 24).padding(.bottom, 10)
                        typeSwitcher
                    }

                    Overline(text: "Product").padding(.top, 24).padding(.bottom, 10)
                    CardGroup {
                        brandRow
                        if brandVersions.count > 1 { variantRow }
                        alignRow
                        FieldRow(label: "Name", text: $sign.name, placeholder: "GT-Air 3")
                        if sign.type != .used {
                            FieldRow(label: "Colour", text: $sign.variant, placeholder: "Solid matte black")
                            FieldRow(label: "Size", text: $sign.size, placeholder: "XL", last: true)
                        }
                        if sign.type == .used {
                            FieldRow(
                                label: "Part no.",
                                text: $sign.partNumber,
                                placeholder: "77411539693",
                                mono: true,
                                last: false
                            )
                        }
                        if sign.type == .used {
                            preOwnedRow
                            if sign.markPreOwned {
                                FieldRow(label: "Condition", text: $sign.condition, placeholder: "Demo · excellent", last: true)
                            }
                        }
                    }

                    Overline(text: "Price").padding(.top, 24).padding(.bottom, 10)
                    CardGroup {
                        if sign.usesComparison {
                            FieldRow(
                                label: "Was",
                                text: $sign.regularPrice,
                                placeholder: "1309.95",
                                keyboard: .decimalPad,
                                tag: priceTag(for: .was),
                                onTagTap: priceTagAction(for: .was)
                            )
                        }
                        if sign.usesComparison {
                            FieldRow(
                                label: "% off",
                                text: $sign.percentOff,
                                placeholder: "10",
                                keyboard: .numberPad,
                                tag: priceTag(for: .percent),
                                onTagTap: priceTagAction(for: .percent)
                            )
                        }
                        FieldRow(
                            label: "Price",
                            text: $sign.price,
                            placeholder: "1178.95",
                            keyboard: .decimalPad,
                            tag: sign.usesComparison ? priceTag(for: .price) : nil,
                            onTagTap: sign.usesComparison ? priceTagAction(for: .price) : nil
                        )
                        priceStyleRow
                    }

                    if sign.usesComparison {
                        Text("Fill in any two of Was, % off and Price and the third is suggested. Type over a suggestion to use your own value.")
                            .font(pt(11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .padding(.top, 8)
                    }

                    HStack {
                        Overline(text: "Feature logos")
                        Spacer()
                        Text("Shared across brands")
                            .font(pt(11))
                            .foregroundColor(Color.white.opacity(0.3))
                    }
                    .padding(.top, 24).padding(.bottom, 10)
                    logoChips

                    if sign.banner != nil {
                        CardGroup {
                            spotRow(label: "Banner", selection: $sign.bannerSpot, headerTitle: "By brand")
                        }
                        .padding(.top, 10)
                        Text("Auto keeps the banner beside the brand logo and moves it to the right when the logo would get too small.")
                            .font(pt(11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .padding(.top, 8)
                    }

                    if sign.type == .used {
                        FitmentEditor(sign: $sign, landscape: landscape)
                    }

                    Overline(text: "Note line").padding(.top, 24).padding(.bottom, 10)
                    CardGroup {
                        FieldRow(label: "Note", text: $sign.note, placeholder: "Confirm fitment with VIN", last: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 150)
            }

            HStack(spacing: 10) {
                Button(action: attemptSave) {
                    Text(saveFlash ?? (sign.libraryID == nil ? "Save" : "Update"))
                        .font(pt(15, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 50)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)

                PillButton(title: "Done", filled: true) { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .background(Color.ptBG.ignoresSafeArea())
        }
        .navigationBarHidden(true)
        .onAppear {
            restoreSuggestionState()
        }
        .onChange(of: sign.regularPrice) { priceFieldEdited(.was) }
        .onChange(of: sign.percentOff) { priceFieldEdited(.percent) }
        .onChange(of: sign.price) { priceFieldEdited(.price) }
        .onChange(of: sign.type) { priceFieldEdited(nil) }
        .alert(DuplicateWarning.title, isPresented: Binding(
            get: { lookAlike != nil },
            set: { if !$0 { lookAlike = nil } }
        )) {
            Button("Open it") {
                if let existing = lookAlike?.match { openExisting(existing) }
            }
            Button("Save anyway") { saveNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(lookAlike.map { DuplicateWarning.message($0) } ?? "")
        }
    }

    // MARK: Saving to the Library

    /// Saves, unless that would add a second copy of a sign the Library already has. Then
    /// it asks first.
    private func attemptSave() {
        if let found = store.lookAlike(for: sign) {
            lookAlike = found
        } else {
            saveNow()
        }
    }

    private func saveNow() {
        let result = saveToLibrary()
        switch result {
        case .saved:         saveFlash = "Saved ✓"
        case .updated:       saveFlash = "Updated ✓"
        case .savedPersonal: saveFlash = "Saved as your copy ✓"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { saveFlash = nil }
    }

    /// Swaps this sign for the Library entry that looks like it. Saving afterwards updates
    /// that entry, or, if it is someone else's, makes a personal copy and a request.
    private func openExisting(_ existing: Sign) {
        var opened = existing.pageCopy()
        opened.id = sign.id
        opened.landscape = sign.landscape
        sign = opened
        saveFlash = "Opened the existing sign"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { saveFlash = nil }
    }

    // MARK: Linked price fields

    private let priceFields: [PriceField] = [.was, .percent, .price]

    private func hasText(_ field: PriceField) -> Bool {
        return !sign.text(for: field).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True while the field still holds exactly what the app wrote into it.
    private func isSuggested(_ field: PriceField) -> Bool {
        guard let written = suggested[field] else { return false }
        return sign.text(for: field) == written
    }

    /// What the other two fields imply for this one, when both were filled in by hand.
    private func impliedValue(for field: PriceField) -> String? {
        let others = priceFields.filter { $0 != field }
        guard others.allSatisfy({ hasText($0) && !isSuggested($0) }) else { return nil }
        return PriceSuggestion.suggestion(
            for: field,
            was: sign.regularPrice,
            percent: sign.percentOff,
            price: sign.price
        )
    }

    private func applySuggestion(_ value: String, to field: PriceField) {
        sign.setText(value, for: field)
        suggested[field] = value
    }

    /// Empties every field that still holds a suggestion, once there is nothing to base it on.
    private func clearSuggestions() {
        for field in priceFields where isSuggested(field) {
            sign.setText("", for: field)
        }
        suggested = [:]
    }

    /// Runs whenever Was, % off or Price changes (or the sign type does, with nil).
    ///
    /// With exactly two fields entered by hand, the third gets a suggestion. A field
    /// the user is typing in is never overwritten, and once they type over a
    /// suggestion it counts as theirs, so it stays put when the other fields change.
    private func priceFieldEdited(_ edited: PriceField?) {
        guard sign.usesComparison else { return }

        if let edited = edited {
            // Our own write landing in the field is not an edit.
            if isSuggested(edited) { return }
            // Typing over or clearing a suggestion makes the value the user's own.
            suggested[edited] = nil
        }

        let entered = priceFields.filter { hasText($0) && !isSuggested($0) }
        if entered.count < 2 {
            clearSuggestions()
            return
        }
        guard entered.count == 2,
              let target = priceFields.first(where: { !entered.contains($0) }),
              target != edited else { return }

        if let value = PriceSuggestion.suggestion(
            for: target,
            was: sign.regularPrice,
            percent: sign.percentOff,
            price: sign.price
        ) {
            applySuggestion(value, to: target)
        } else {
            clearSuggestions()
        }
    }

    /// A saved sign whose price still follows from its Was and % off keeps treating
    /// the price as a suggestion, so editing Was or % off updates it again.
    private func restoreSuggestionState() {
        guard sign.usesComparison,
              let implied = PriceSuggestion.derivePrice(was: sign.regularPrice, percent: sign.percentOff),
              let stored = PriceSuggestion.amount(sign.price),
              stored == PriceSuggestion.amount(implied) else { return }
        suggested[.price] = sign.price
    }

    /// "Suggested" on a field holding a suggestion; "Use $1178.95" on an empty field
    /// whose value the other two fields imply, so a cleared suggestion can be brought back.
    private func priceTag(for field: PriceField) -> String? {
        if isSuggested(field) { return "Suggested" }
        guard !hasText(field), let value = impliedValue(for: field) else { return nil }
        return "Use " + (field == .percent ? value + "%" : "$" + value)
    }

    private func priceTagAction(for field: PriceField) -> (() -> Void)? {
        guard !isSuggested(field), !hasText(field), let value = impliedValue(for: field) else { return nil }
        return { applySuggestion(value, to: field) }
    }

    /// Changing the type re-flows which fields the editor shows and which banner the
    /// sign prints. Nothing typed is discarded, so switching back restores the sign.
    private var typeSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SignType.allCases) { type in
                    let active = sign.type == type
                    Button(action: {
                        guard sign.type != type else { return }
                        withAnimation(.easeOut(duration: 0.2)) { sign.type = type }
                    }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(typeTone(type))
                                .frame(width: 7, height: 7)
                            Text(typeShortName(type))
                                .font(pt(13, active ? .semibold : .medium))
                                .foregroundColor(active ? .white : Color.white.opacity(0.55))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(active ? Color.ptAccent.opacity(0.18) : Color.ptCard)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                active ? Color.ptAccent : Color.ptHair,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func typeShortName(_ type: SignType) -> String {
        switch type {
        case .regular:   return "Regular"
        case .sale:      return "Sale"
        case .clearance: return "End of season"
        case .used:      return "Part"
        case .apparel:   return "Apparel"
        }
    }

    private func typeTone(_ type: SignType) -> Color {
        switch type {
        case .sale:      return Color(hex: 0xE00000)
        case .clearance: return Color(hex: 0x4E9A18)
        case .used:      return Color(hex: 0x215E99)
        default:         return Color.white.opacity(0.45)
        }
    }

    /// A parts sign covers both new and used stock; this decides whether it prints
    /// the PRE-OWNED flag and asks for a condition line.
    private var preOwnedRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Pre-owned")
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                Toggle("", isOn: $sign.markPreOwned)
                    .labelsHidden()
                    .tint(.ptAccent)
                Spacer()
                Text(sign.markPreOwned ? "Prints the flag" : "New part")
                    .font(pt(12))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            if sign.markPreOwned {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
        }
    }

    private var brandRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Brand")
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                Picker("", selection: $sign.brand) {
                    ForEach(logos.names(.brand), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .onChange(of: sign.brand) { _ in sign.brandVariant = nil }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    /// Whether the logos find their own place over the name, or are held flush left.
    private var alignRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Align")
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                Picker("", selection: Binding(
                    get: { sign.logoAlignment ?? .auto },
                    set: { sign.logoAlignment = $0 == .auto ? nil : $0 }
                )) {
                    Text("Auto").tag(LogoAlignment.auto)
                    Text("Left").tag(LogoAlignment.left)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var brandVersions: [LogoAsset] {
        return logos.versions(of: sign.brand, kind: .brand)
    }

    /// Only shown when a brand has more than one mark on file.
    private var variantRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Logo")
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                Picker("", selection: Binding(
                    get: { sign.brandVariant ?? "" },
                    set: { sign.brandVariant = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(brandVersions) { version in
                        Text(version.variantLabel.isEmpty ? "Standard" : version.variantLabel)
                            .tag(version.variantLabel)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var priceStyleRow: some View {
        HStack(spacing: 12) {
            Text("Style")
                .font(pt(14))
                .foregroundColor(Color.white.opacity(0.5))
                .frame(width: 78, alignment: .leading)

            HStack(spacing: 3) {
                styleOption(title: "$588⁶⁰", on: sign.splitCents) { sign.splitCents = true }
                styleOption(title: "$588.60", on: !sign.splitCents) { sign.splitCents = false }
            }
            .padding(3)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func styleOption(title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(pt(13, .medium))
                .foregroundColor(on ? .white : Color.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? Color.ptAccent : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    /// Auto, the header row, or the right-hand side of the sign.
    private func spotRow(label: String, selection: Binding<MarkSpot?>, headerTitle: String) -> some View {
        func title(_ spot: MarkSpot) -> String {
            switch spot {
            case .auto:   return "Auto"
            case .header: return headerTitle
            case .side:   return "Right"
            }
        }
        return HStack(spacing: 12) {
            Text(label)
                .font(pt(14))
                .foregroundColor(Color.white.opacity(0.5))
                .frame(width: 78, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(MarkSpot.allCases, id: \.self) { spot in
                    styleOption(title: title(spot), on: (selection.wrappedValue ?? .auto) == spot) {
                        selection.wrappedValue = spot == .auto ? nil : spot
                    }
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var logoChips: some View {
        FlowChips(options: logos.names(.feature), selected: sign.featureLogos) { name in
            if let i = sign.featureLogos.firstIndex(of: name) {
                sign.featureLogos.remove(at: i)
            } else {
                sign.featureLogos.append(name)
            }
        }
    }
}

struct FlowChips: View {
    let options: [String]
    let selected: [String]
    let toggle: (String) -> Void

    private var rows: [[String]] {
        var out: [[String]] = []
        var row: [String] = []
        for option in options {
            row.append(option)
            if row.count == 2 {
                out.append(row)
                row = []
            }
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { name in
                        let on = selected.contains(name)
                        Button(action: { toggle(name) }) {
                            Text(name)
                                .font(pt(13, .medium))
                                .foregroundColor(on ? Color(hex: 0xC7C9FF) : Color.ptMid)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule().fill(on ? Color.ptAccent.opacity(0.18) : Color.clear)
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        on ? Color.ptAccent : Color.white.opacity(0.14),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
