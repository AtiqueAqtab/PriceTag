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
    @ObservedObject private var logos = LogoLibrary.shared
    @Binding var sign: Sign
    var saveToLibrary: () -> Void

    @State private var fitmentText: String = ""

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
                        Overline(text: sign.type.title)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                    ScaledSign(sign: sign)
                        .padding(16)
                        .background(Color.ptInset)
                        .cornerRadius(12)

                    Text("Live preview · actual print size 7.5 × 2.375 in")
                        .font(pt(11))
                        .foregroundColor(Color.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    HStack {
                        Overline(text: "Sign type")
                        Spacer()
                        Text("Switch any time — entries are kept")
                            .font(pt(11))
                            .foregroundColor(Color.white.opacity(0.3))
                    }
                    .padding(.top, 24).padding(.bottom, 10)
                    typeSwitcher

                    Overline(text: "Product").padding(.top, 24).padding(.bottom, 10)
                    CardGroup {
                        brandRow
                        if brandVersions.count > 1 { variantRow }
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
                        if sign.type == .sale || sign.type == .clearance || sign.type == .used {
                            FieldRow(label: "Was", text: $sign.regularPrice, placeholder: "1309.95", keyboard: .decimalPad)
                        }
                        if sign.type == .clearance || sign.type == .sale || sign.type == .used {
                            FieldRow(label: "% off", text: $sign.percentOff, placeholder: "10", keyboard: .numberPad)
                        }
                        FieldRow(label: "Price", text: $sign.price, placeholder: "1178.95", keyboard: .decimalPad)
                        priceStyleRow
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

                    if sign.type == .used {
                        Overline(text: "Fitment — one per line").padding(.top, 24).padding(.bottom, 10)
                        TextEditor(text: $fitmentText)
                            .font(pt(14, .medium))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(10)
                            .background(Color.ptCard)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.ptHair, lineWidth: 1)
                            )
                            .onChange(of: fitmentText) { newValue in
                                sign.fitment = newValue
                                    .components(separatedBy: "\n")
                                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            }
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
                Button(action: { saveToLibrary() }) {
                    Text("Save")
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
        .onAppear { fitmentText = sign.fitment.joined(separator: "\n") }
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
        case .clearance: return "Clearance"
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
