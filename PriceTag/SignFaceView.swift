//
//  SignFaceView.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-13.
//

import SwiftUI

/// The sign as it appears on paper.
///
/// Laid out at 540 × 171 points (7.5 × 2.375 in). The same view is
/// scaled down for the on-screen preview and drawn full size in the PDF.
struct SignFaceView: View {

    let sign: Sign

    /// The sign's size in points at print resolution.
    static let printSize = CGSize(width: 540, height: 171)

    // Swap this for .custom("Archivo Black", size:) once the font is added.
    private func heavyFont(_ size: CGFloat) -> Font {
        return Font.system(size: size, weight: .black)
    }

    private var chips: [String] {
        var parts: [String] = []
        if !sign.variant.isEmpty { parts.append(sign.variant) }
        if !sign.size.isEmpty { parts.append("(" + sign.size + ")") }
        if !sign.condition.isEmpty { parts.append(sign.condition) }
        return parts.map { $0.uppercased() }
    }

    private var nameSize: CGFloat {
        let dense = !sign.partNumber.isEmpty || !sign.fitment.isEmpty || !sign.note.isEmpty
        let tiers: [CGFloat] = dense ? [21, 25, 30, 37] : [25, 31, 39, 46]
        let n = sign.name.count
        if n > 24 { return tiers[0] }
        if n > 16 { return tiers[1] }
        if n > 10 { return tiers[2] }
        return tiers[3]
    }

    private var dollars: String {
        if !sign.splitCents { return sign.price }
        let parts = sign.price.split(separator: ".")
        if let first = parts.first { return String(first) }
        return sign.price
    }

    private var centsPart: String {
        if !sign.splitCents { return "" }
        if !sign.cents.isEmpty { return sign.cents }
        let parts = sign.price.split(separator: ".")
        if parts.count > 1 { return String(parts[1]) }
        return ""
    }

    /// Fills the price column: the cap only drops when a was-price or a
    /// percent flag has to share the same column.
    private var priceSize: CGFloat {
        let chars = CGFloat(dollars.count + 1) + CGFloat(centsPart.count) * 0.45
        let crowded = !sign.regularPrice.isEmpty && !sign.percentOff.isEmpty
        let cap: CGFloat = crowded ? 78 : 88
        return min(cap, 206 / (0.62 * chars))
    }

    /// Red only where there is a was-price to beat; otherwise ink.
    private var priceColor: Color {
        if !sign.regularPrice.isEmpty { return Color(red: 0.88, green: 0.00, blue: 0.05) }
        return Color(red: 0.07, green: 0.07, blue: 0.07)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            leftColumn
            Rectangle()
                .fill(Color.black)
                .frame(width: 2)
            rightColumn
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(width: SignFaceView.printSize.width, height: SignFaceView.printSize.height)
        .background(Color.white)
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2))
    }

    /// Bright, print-safe flags: red for sale, orange for clearance, blue for pre-owned.
    private var bannerColor: Color {
        switch sign.type {
        case .sale:      return Color(red: 0.88, green: 0.00, blue: 0.05)
        case .clearance: return Color(red: 0.96, green: 0.45, blue: 0.00)
        case .used:      return Color(red: 0.00, green: 0.36, blue: 0.75)
        default:         return .black
        }
    }

    private var brandImage: UIImage? {
        return LogoLibrary.shared.image(
            named: sign.brand,
            kind: .brand,
            variant: sign.brandVariant ?? ""
        )
    }

    /// Roughly square marks (the BMW roundel) waste the header row, so they
    /// move into a left gutter at full height with the text beside them.
    private var roundelBrand: Bool {
        guard let image = brandImage, image.size.height > 0 else { return false }
        return image.size.width / image.size.height < 1.6
    }

    private var showsHeaderRow: Bool {
        if !roundelBrand { return true }
        return !sign.featureLogos.isEmpty || sign.banner != nil
    }

    private var leftColumn: some View {
        HStack(alignment: .center, spacing: 13) {
            if roundelBrand, let image = brandImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            }
            textBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeaderRow {
                HStack(spacing: 6) {
                    if !roundelBrand {
                        LogoPlate(name: sign.brand, kind: .brand, variant: sign.brandVariant ?? "")
                    }
                    ForEach(sign.featureLogos, id: \.self) { logo in
                        LogoPlate(name: logo, kind: .feature)
                    }
                    if let banner = sign.banner {
                        Text(banner)
                            .font(.system(size: 11, weight: .heavy))
                            .kerning(1.4)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(bannerColor)
                    }
                }
                .padding(.bottom, 6)
            }

            Text(sign.name.uppercased())
                .font(heavyFont(nameSize))
                .foregroundColor(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if !chips.isEmpty {
                Text(chips.joined(separator: "   "))
                    .font(.system(size: 16, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(.black)
                    .padding(.top, 5)
            }

            if !sign.partNumber.isEmpty {
                Text(sign.partNumber)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.75))
                    .padding(.top, 5)
            }

            Spacer(minLength: 4)

            if !sign.fitment.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("FITS:")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.2)
                        .foregroundColor(.black)
                    Text(sign.fitment.joined(separator: "   "))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.black.opacity(0.8))
                        .lineLimit(2)
                }
            }

            if !sign.note.isEmpty {
                Text(sign.note.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.7)
                    .foregroundColor(Color(red: 0.88, green: 0, blue: 0))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if !sign.percentOff.isEmpty {
                Text(sign.percentOff + "% OFF")
                    .font(heavyFont(24))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.31, green: 0.60, blue: 0.09))
            }

            if !sign.regularPrice.isEmpty {
                HStack(spacing: 6) {
                    Text("WAS")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.4)
                        .foregroundColor(.black.opacity(0.55))
                    Text("$" + sign.regularPrice)
                        .font(.system(size: 18, weight: .bold))
                        .strikethrough()
                        .foregroundColor(.black.opacity(0.65))
                }
            }

            HStack(alignment: .top, spacing: 0) {
                Text("$" + dollars)
                    .font(heavyFont(priceSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if !centsPart.isEmpty {
                    Text(centsPart)
                        .font(heavyFont(priceSize * 0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.top, priceSize * 0.1)
                }
            }
            .foregroundColor(priceColor)
        }
        .frame(maxWidth: 214, alignment: .trailing)
    }
}

/// Prints the stored artwork when there is any, otherwise a labelled box.
struct LogoPlate: View {
    @ObservedObject private var logos = LogoLibrary.shared

    let name: String
    var kind: LogoKind = .brand
    var variant: String = ""

    private var height: CGFloat { return kind == .brand ? 42 : 28 }
    private var maxWidth: CGFloat { return kind == .brand ? 190 : 100 }

    var body: some View {
        if let image = logos.image(named: name, kind: kind, variant: variant) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth, maxHeight: height)
        } else {
            Text(name.uppercased())
                .font(.system(size: kind == .brand ? 10 : 9, weight: .bold))
                .kerning(1)
                .foregroundColor(.black.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            Color.black.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                )
        }
    }
}

/// Shows a full-size sign scaled down to whatever width it is given.
struct ScaledSign: View {
    let sign: Sign

    var body: some View {
        GeometryReader { geo in
            SignFaceView(sign: sign)
                .scaleEffect(geo.size.width / SignFaceView.printSize.width, anchor: .topLeading)
        }
        .aspectRatio(
            SignFaceView.printSize.width / SignFaceView.printSize.height,
            contentMode: .fit
        )
    }
}

#Preview {
    ScaledSign(sign: Sign(
        type: .clearance,
        brand: "Shoei",
        name: "GT-Air 3",
        variant: "Solid matte black",
        size: "XL",
        price: "1043.95",
        regularPrice: "1159.95",
        percentOff: "10",
        splitCents: false
    ))
    .padding()
}
