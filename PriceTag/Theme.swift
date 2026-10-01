//
//  Theme.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI

/// Colours, font sizes and shared controls used across the app.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    static let ptBG     = Color(hex: 0x0A0A0A)
    static let ptCard   = Color(hex: 0x111111)
    static let ptInset  = Color(hex: 0x1A1A1A)
    static let ptAccent = Color(hex: 0x6366F1)
    static let ptHair   = Color.white.opacity(0.08)
    static let ptDim    = Color.white.opacity(0.40)
    static let ptMid    = Color.white.opacity(0.60)
}

/// Swap the body for .custom("SpaceGrotesk-Medium", size:) if you add the font.
func pt(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    return Font.system(size: size, weight: weight)
}

/// Uppercase tracked label, the design system's only label treatment.
struct Overline: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(pt(11, .medium))
            .kerning(1.1)
            .foregroundColor(Color.white.opacity(0.35))
    }
}

struct PillButton: View {
    let title: String
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(pt(15, .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule().fill(filled ? Color.ptAccent : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        filled ? Color.clear : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

struct CardGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.ptCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.ptHair, lineWidth: 1)
            )
    }
}

struct FieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var mono: Bool = false
    var last: Bool = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                TextField("", text: $text, prompt:
                    Text(placeholder).foregroundColor(Color.white.opacity(0.28))
                )
                .font(mono ? Font.system(size: 15, weight: .medium, design: .monospaced) : pt(15, .medium))
                .foregroundColor(.white)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if !last {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
