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

    /// True for the landscape layout: the same design, 27 pt taller, printed 4/3 larger
    /// so it fills a half of a sideways sheet (720 × 264 pt).
    var landscape: Bool = false

    /// The sign's size in points at print resolution.
    static let printSize = CGSize(width: 540, height: 171)
    /// How much taller the landscape layout is before it is scaled up.
    static let landscapeExtra: CGFloat = 27

    /// The height this sign is laid out at.
    private var layoutHeight: CGFloat {
        return SignFaceView.printSize.height + (landscape ? SignFaceView.landscapeExtra : 0)
    }

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
        let dense = !sign.partNumber.isEmpty || sign.hasFitment || !sign.note.isEmpty
        let tiers: [CGFloat] = dense ? [19, 23, 28, 34] : [23, 29, 36, 42]
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
        let hasWas = !sign.printedRegularPrice.isEmpty
        let hasPercent = !sign.printedPercentOff.isEmpty
        // Feature logos that moved over get a row of their own when there is no % flag to share.
        let crowded = hasWas && hasPercent
        let cap: CGFloat = (crowded ? 78 : 88) - wasSlotExtraHeight / 1.2
        return min(cap, 206 / (0.62 * chars))
    }

    /// Red only where there is a was-price to beat; otherwise ink.
    private var priceColor: Color {
        if !sign.printedRegularPrice.isEmpty { return Color(red: 0.88, green: 0.00, blue: 0.05) }
        return Color(red: 0.07, green: 0.07, blue: 0.07)
    }

    /// Extra space above the content, so nothing crowds the top edge.
    private static let topInset: CGFloat = 10
    /// The header row is never shorter than this, so the product name starts at the
    /// same height whatever the brand logo's shape.
    private static let headerRowHeight: CGFloat = 36

    /// A right column with a % OFF flag, a WAS price or a row of logos starts at the
    /// top, level with the header row. A bare price is centered in the column.
    private var rightColumnAnchoredTop: Bool {
        return !sign.printedPercentOff.isEmpty
            || !sign.printedRegularPrice.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // The divider runs the full height, down to the fitment strip when there is one.
                Rectangle()
                    .fill(Color.black)
                    .frame(width: SignFaceView.dividerWidth)
                    .padding(.leading, SignFaceView.leftWidth + SignFaceView.columnGap)
                // Every sign starts its content at the same height; a note stays at the bottom.
                HStack(alignment: .top, spacing: SignFaceView.columnGap) {
                    leftColumn
                        .frame(maxHeight: .infinity, alignment: .top)
                    Color.clear.frame(width: SignFaceView.dividerWidth, height: 0)
                    rightColumn
                        .frame(maxHeight: .infinity, alignment: rightColumnAnchoredTop ? .top : .center)
                }
                .padding(.top, SignFaceView.topInset)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)

            if sign.hasFitment {
                fitmentStrip
            }
        }
        .padding(.horizontal, SignFaceView.sidePadding)
        .padding(.vertical, 12)
        .frame(width: SignFaceView.printSize.width, height: layoutHeight)
        .background(Color.white)
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2))
    }

    // MARK: Fitment strip

    private static let fitsLabelWidth: CGFloat = 30

    /// Rows of tags the strip may use. A sign with a header row has less room, and the
    /// landscape layout has a row more.
    private var fitmentMaxRows: Int {
        return (showsHeaderRow ? 1 : 2) + (landscape ? 1 : 0)
    }

    /// How the tags wrap on this sign. The editor reads `hidden` to warn about overflow.
    var fitmentPlan: FitmentLayout.Plan {
        let width = SignFaceView.printSize.width - 2 * SignFaceView.sidePadding
            - SignFaceView.fitsLabelWidth - 8
        return FitmentLayout.plan(tags: sign.fitTags, width: width, maxRows: fitmentMaxRows)
    }

    private var fitmentStrip: some View {
        let plan = fitmentPlan
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 1.5)
            HStack(alignment: .top, spacing: 8) {
                Text("FITS")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(.black)
                    .frame(width: SignFaceView.fitsLabelWidth, alignment: .leading)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(plan.lines.indices, id: \.self) { row in
                        HStack(spacing: FitmentLayout.tagGap) {
                            ForEach(plan.lines[row].indices, id: \.self) { col in
                                fitTagView(plan.lines[row][col], size: plan.fontSize)
                            }
                        }
                    }
                }
            }
            .padding(.top, 5)
        }
    }

    private func fitTagView(_ tag: FitTag, size: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(tag.models)
                .font(.system(size: size, weight: .heavy))
            if !tag.years.isEmpty {
                Text(tag.years)
                    .font(.system(size: size, weight: .medium))
            }
        }
        .foregroundColor(.black)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, FitmentLayout.tagPadding)
        .padding(.vertical, 1.5)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.black, lineWidth: 1)
        )
    }

    // MARK: Where the marks go

    // Column geometry, shared by the layout and by the width maths below.
    private static let sidePadding: CGFloat = 15
    private static let columnGap: CGFloat = 16
    private static let dividerWidth: CGFloat = 2
    private static let rightWidth: CGFloat = 214
    private static let leftWidth: CGFloat =
        printSize.width - 2 * sidePadding - 2 * columnGap - dividerWidth - rightWidth
    private static let markGap: CGFloat = 6

    /// Where a group of marks prints.
    private enum MarkSlot {
        /// The header row above the product name, beside the brand logo.
        case header
        /// The empty space to the left of the % OFF flag.
        case flag
        /// The empty space to the left of the WAS price.
        case was
    }

    /// Where the banner and the feature logos print, and how far each mark shrinks.
    private struct MarkPlan {
        var bannerSlot: MarkSlot = .header
        /// Long banners break over two lines only when one line would squeeze the brand too far.
        var bannerTwoLine = false
        var brandScale: CGFloat = 1
    }

    /// The smallest the brand mark is allowed to get before anything moves out of the
    /// header row (the size of the BMW Motorrad mark beside an M logo and a SALE banner).
    private static let minBrandScale: CGFloat = 0.62
    /// The brand mark never shrinks below this. The feature logos always stay beside
    /// it, so this is as far as it goes to fit them.
    private static let hardMinBrandScale: CGFloat = 0.4

    private func textWidth(_ text: String, size: CGFloat, weight: UIFont.Weight, kern: CGFloat = 0) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .kern: kern
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private static let maxMarkGap: CGFloat = 28
    /// The space the header row aims for between the brand, the logos and the banner.
    private static let headerGap: CGFloat = 16

    /// Spacing that depends on how many marks share a row: the free width is split
    /// evenly between the marks and both ends, so few marks sit well apart and
    /// many marks pack together. Never tighter than markGap, never looser than maxMarkGap.
    private func markSpacing(_ widths: [CGFloat], in available: CGFloat) -> CGFloat {
        guard !widths.isEmpty else { return SignFaceView.markGap }
        let free = available - widths.reduce(0, +)
        let even = free / CGFloat(widths.count + 1)
        return min(SignFaceView.maxMarkGap, max(SignFaceView.markGap, even))
    }

    private var headerWidth: CGFloat {
        roundelBrand ? SignFaceView.leftWidth - 80 - 13 : SignFaceView.leftWidth
    }

    /// Widths of the marks that print in the header row, brand first, after scaling.
    private var headerWidths: [CGFloat] {
        let plan = markPlan
        var widths: [CGFloat] = []
        if !roundelBrand {
            widths.append(
                LogoPlate.printedSize(name: sign.brand, kind: .brand, variant: sign.brandVariant ?? "").width
                    * plan.brandScale
            )
        }
        widths.append(contentsOf: sign.featureLogos.map {
            LogoPlate.printedSize(name: $0, kind: .feature).width
        })
        if plan.bannerSlot == .header && sign.banner != nil {
            widths.append(bannerWidth(twoLine: plan.bannerTwoLine))
        }
        return widths
    }

    /// How far the header marks sit in from the left edge of the text.
    ///
    /// Automatic: centred over the product name, so a short name keeps the logo close and
    /// a long one gives it room, but never further in than the logo would sit centred in
    /// its own slot. A mark row as wide as the name, or wider, stays flush left.
    private var headerInset: CGFloat {
        if sign.logoAlignment == .left { return 0 }
        let widths = headerWidths
        guard !widths.isEmpty else { return 0 }
        let row = widths.reduce(0, +) + headerSpacing * CGFloat(widths.count - 1)
        let name = min(headerWidth, textWidth(sign.name.uppercased(), size: nameSize, weight: .black))
        let slot = min(headerWidth, SignFaceView.brandSlotWidth)
        return max(0, min((name - row) / 2, (slot - row) / 2))
    }

    /// The box a brand mark is fitted into, which is also the room it is centred in.
    private static let brandSlotWidth: CGFloat = 190

    /// The gap between header marks: the aim, squeezed only when the row is full.
    private var headerSpacing: CGFloat {
        let widths = headerWidths
        guard widths.count > 1 else { return SignFaceView.headerGap }
        let free = headerWidth - widths.reduce(0, +)
        let even = free / CGFloat(widths.count - 1)
        return min(SignFaceView.headerGap, max(SignFaceView.markGap, even))
    }

    /// Width the WAS row takes in the right column (label, struck price, a little slack).
    private var wasRowWidth: CGFloat {
        if sign.printedRegularPrice.isEmpty { return 0 }
        return textWidth("WAS", size: 11, weight: .bold, kern: 1.4)
            + 6
            + textWidth("$" + sign.printedRegularPrice, size: 16, weight: .bold)
            + 6
    }

    private var flagSlotRoom: CGFloat {
        percentFlagWidth > 0 ? SignFaceView.rightWidth - percentFlagWidth : 0
    }

    private var wasSlotRoom: CGFloat {
        wasRowWidth > 0 ? SignFaceView.rightWidth - wasRowWidth : 0
    }

    private func rowWidth(_ widths: [CGFloat], gap: CGFloat = SignFaceView.markGap) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
    }

    /// A banner prints on one line. When one line costs the brand too much room,
    /// long banners such as END OF SEASON break at the space that leaves the two
    /// lines closest in length.
    private func bannerLines(twoLine: Bool) -> [String] {
        guard let banner = sign.banner else { return [] }
        guard twoLine else { return [banner] }
        let words = banner.split(separator: " ").map(String.init)
        guard banner.count > 9, words.count > 1 else { return [banner] }
        var splitAt = 1
        var shortestLongest = Int.max
        for i in 1..<words.count {
            let first = words[..<i].joined(separator: " ")
            let second = words[i...].joined(separator: " ")
            let longest = max(first.count, second.count)
            if longest < shortestLongest {
                shortestLongest = longest
                splitAt = i
            }
        }
        return [
            words[..<splitAt].joined(separator: " "),
            words[splitAt...].joined(separator: " ")
        ]
    }

    private func bannerWidth(twoLine: Bool) -> CGFloat {
        let widest = bannerLines(twoLine: twoLine)
            .map { textWidth($0, size: 11, weight: .heavy, kern: 1.4) }
            .max() ?? 0
        return widest > 0 ? widest + 16 : 0
    }

    private var percentFlagWidth: CGFloat {
        if sign.printedPercentOff.isEmpty { return 0 }
        return textWidth(sign.printedPercentOff + "% OFF", size: 22, weight: .black) + 14 + 6
    }

    /// Decides where the banner prints and how far the brand mark shrinks.
    ///
    /// The brand logo and the feature logos always stay together in the header row.
    /// By default the banner joins them there, and the brand logo shrinks to make
    /// room, down to minBrandScale. Only when that is not enough does the banner
    /// move to the empty space beside the % OFF flag (or the WAS price). The editor
    /// can force the banner to either place.
    private var markPlan: MarkPlan {
        let gap = SignFaceView.markGap
        let roundel = roundelBrand
        let brandWidth: CGFloat = roundel
            ? 0
            : LogoPlate.printedSize(name: sign.brand, kind: .brand, variant: sign.brandVariant ?? "").width
        let featureWidths = sign.featureLogos.map {
            LogoPlate.printedSize(name: $0, kind: .feature).width
        }
        let bannerOne = bannerWidth(twoLine: false)
        let bannerTwo = bannerWidth(twoLine: true)
        let bannerSpot = sign.bannerSpot ?? .auto
        var bannerCurrent = bannerOne
        var bannerInHeader = bannerOne > 0
        var plan = MarkPlan()

        // How much of the brand's full width the header row leaves it. A roundel sits
        // in its own gutter, so there it is all or nothing: do the other marks fit.
        func headerRatio() -> CGFloat {
            var others = featureWidths
            if bannerInHeader { others.append(bannerCurrent) }
            if roundel { return rowWidth(others, gap: SignFaceView.headerGap) <= headerWidth ? 1 : 0 }
            guard brandWidth > 0 else { return 1 }
            let used = others.isEmpty ? 0 : rowWidth(others, gap: SignFaceView.headerGap) + SignFaceView.headerGap
            return (headerWidth - used) / brandWidth
        }

        // Moves the banner to the right column, on one line if it fits and on two if not.
        func moveBannerRight() {
            // Beside the flag the banner joins it as one tag, so it needs no gaps.
            func firstSlot(fitting width: CGFloat) -> MarkSlot? {
                if width <= flagSlotRoom { return .flag }
                if width + 2 * gap <= wasSlotRoom { return .was }
                return nil
            }
            if let slot = firstSlot(fitting: bannerOne) {
                plan.bannerSlot = slot
            } else if bannerTwo < bannerOne, let slot = firstSlot(fitting: bannerTwo) {
                plan.bannerSlot = slot
                plan.bannerTwoLine = true
                bannerCurrent = bannerTwo
            } else {
                return
            }
            bannerInHeader = false
        }

        if bannerInHeader {
            if bannerSpot == .side {
                moveBannerRight()
            } else if bannerSpot == .auto && headerRatio() < SignFaceView.minBrandScale {
                moveBannerRight()
            }
        }

        if !roundel, brandWidth > 0 {
            var ratio = headerRatio()
            if bannerInHeader && bannerTwo > 0 && bannerTwo < bannerOne
                && ratio < SignFaceView.minBrandScale {
                plan.bannerTwoLine = true
                bannerCurrent = bannerTwo
                ratio = headerRatio()
            }
            plan.brandScale = min(1, max(SignFaceView.hardMinBrandScale, ratio))
        }
        return plan
    }

    private func bannerBadge(twoLine: Bool, stretch: Bool = false) -> some View {
        Text(bannerLines(twoLine: twoLine).joined(separator: "\n"))
            .font(.system(size: 11, weight: .heavy))
            .kerning(1.4)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .fixedSize()
            .padding(.horizontal, 8)
            // Beside the % OFF flag the banner takes the flag's height. Two lines of text with the
            // usual padding stand a few points taller than the flag, so they get less here.
            .padding(.vertical, stretch && twoLine ? 2 : 4)
            .frame(maxHeight: stretch ? .infinity : nil)
            .background(bannerColor)
    }

    private func percentFlag(stretch: Bool = false) -> some View {
        Text(sign.printedPercentOff + "% OFF")
            .font(heavyFont(22))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            // Beside the banner both take the taller of the two, so they always match.
            .frame(maxHeight: stretch ? .infinity : nil)
            .background(Color(red: 0.31, green: 0.60, blue: 0.09))
    }

    /// The banner, when it prints in `slot` of the right column, centered in `width`.
    private func sideMarks(in slot: MarkSlot, width: CGFloat) -> some View {
        let plan = markPlan
        return HStack(spacing: 0) {
            if sign.banner != nil && plan.bannerSlot == slot {
                bannerBadge(twoLine: plan.bannerTwoLine)
            }
        }
        .frame(width: width, alignment: .center)
    }

    private func hasSideMarks(in slot: MarkSlot) -> Bool {
        return sign.banner != nil && markPlan.bannerSlot == slot
    }

    /// Height the banner beside the WAS price adds beyond the row itself, so the
    /// price can give that much back.
    private var wasSlotExtraHeight: CGFloat {
        let plan = markPlan
        guard sign.banner != nil && plan.bannerSlot == .was else { return 0 }
        let height = CGFloat(bannerLines(twoLine: plan.bannerTwoLine).count) * 13.4 + 8
        return max(0, height - 22)
    }

    /// Bright, print-safe flags: red for sale, orange for end of season, blue for pre-owned.
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
        let plan = markPlan
        let featuresInHeader = !sign.featureLogos.isEmpty
        let bannerInHeader = sign.banner != nil && plan.bannerSlot == .header
        return featuresInHeader || bannerInHeader
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
        .frame(width: SignFaceView.leftWidth, alignment: .leading)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeaderRow {
                HStack(spacing: headerSpacing) {
                    if !roundelBrand {
                        LogoPlate(
                            name: sign.brand,
                            kind: .brand,
                            variant: sign.brandVariant ?? "",
                            scale: markPlan.brandScale
                        )
                    }
                    ForEach(sign.featureLogos, id: \.self) { logo in
                        LogoPlate(name: logo, kind: .feature)
                    }
                    if sign.banner != nil && markPlan.bannerSlot == .header {
                        bannerBadge(twoLine: markPlan.bannerTwoLine)
                    }
                }
                .frame(minHeight: SignFaceView.headerRowHeight)
                .padding(.leading, headerInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }

            Text(sign.name.uppercased())
                .font(heavyFont(nameSize))
                .foregroundColor(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if !chips.isEmpty {
                Text(chips.joined(separator: "   "))
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(0.6)
                    .foregroundColor(.black.opacity(0.8))
                    .padding(.top, 6)
            }

            if !sign.partNumber.isEmpty {
                Text(sign.partNumber)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.75))
                    .padding(.top, 5)
            }

            Spacer(minLength: 4)

            if !sign.note.isEmpty {
                Text(sign.note.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundColor(Color(red: 0.88, green: 0, blue: 0))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if !sign.printedPercentOff.isEmpty {
                if hasSideMarks(in: .flag) {
                    // The banner and the flag read as one two-colour tag.
                    HStack(spacing: 0) {
                        bannerBadge(twoLine: markPlan.bannerTwoLine, stretch: true)
                        percentFlag(stretch: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    percentFlag()
                }
            }

            if !sign.printedRegularPrice.isEmpty {
                HStack(spacing: 0) {
                    if hasSideMarks(in: .was) {
                        sideMarks(in: .was, width: SignFaceView.rightWidth - wasRowWidth)
                    }
                    HStack(spacing: 6) {
                        Text("WAS")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.4)
                            .foregroundColor(.black.opacity(0.4))
                        Text("$" + sign.printedRegularPrice)
                            .font(.system(size: 16, weight: .bold))
                            .strikethrough()
                            .foregroundColor(.black.opacity(0.55))
                    }
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
        .frame(width: SignFaceView.rightWidth, alignment: .trailing)
    }
}

/// Prints the stored artwork when there is any, otherwise a labelled box.
struct LogoPlate: View {
    @ObservedObject private var logos = LogoLibrary.shared

    let name: String
    var kind: LogoKind = .brand
    var variant: String = ""
    /// 1 prints the mark at full size; smaller values shrink it to make room.
    var scale: CGFloat = 1

    /// The size a mark prints at: as large as its box allows (brands 190 x 42 pt,
    /// feature logos 100 x 28 pt) with no empty slot around it, so neighbouring
    /// marks sit close together. Artwork that is missing prints as a labelled box.
    static func printedSize(name: String, kind: LogoKind, variant: String = "") -> CGSize {
        let boxWidth: CGFloat = kind == .brand ? 190 : 100
        var boxHeight: CGFloat = kind == .brand ? 42 : 28
        if let image = LogoLibrary.shared.image(named: name, kind: kind, variant: variant),
           image.size.width > 0, image.size.height > 0 {
            // Near-square marks such as Gore-Tex read poorly at the usual height, so they print taller.
            if kind == .feature && image.size.width / image.size.height < 1.4 { boxHeight = 36 }
            let fit = min(boxWidth / image.size.width, boxHeight / image.size.height)
            return CGSize(width: image.size.width * fit, height: image.size.height * fit)
        }
        let font = UIFont.systemFont(ofSize: kind == .brand ? 10 : 9, weight: .bold)
        let label = name.uppercased() as NSString
        let width = ceil(label.size(withAttributes: [.font: font, .kern: 1]).width) + 12
        return CGSize(width: width, height: 20)
    }

    var body: some View {
        if let image = logos.image(named: name, kind: kind, variant: variant) {
            let size = LogoPlate.printedSize(name: name, kind: kind, variant: variant)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width * scale, height: size.height * scale)
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
    var landscape: Bool = false

    var body: some View {
        let height = SignFaceView.printSize.height + (landscape ? SignFaceView.landscapeExtra : 0)
        return GeometryReader { geo in
            SignFaceView(sign: sign, landscape: landscape)
                .scaleEffect(geo.size.width / SignFaceView.printSize.width, anchor: .topLeading)
        }
        .aspectRatio(SignFaceView.printSize.width / height, contentMode: .fit)
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
