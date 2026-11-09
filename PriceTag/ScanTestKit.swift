//
//  ScanTestKit.swift
//  PriceTag
//
//  Test data for the scanner. Only in builds run from Xcode.
//

#if DEBUG
import SwiftUI
import UIKit

/// Library signs for the scanner to find, and printed signs to scan: some match the
/// Library (one with a changed price), some are not in it at all.
enum ScanTestKit {

    /// A sign that is expected to come out of the scanner a certain way.
    struct TestSign: Identifiable {
        var id: String { return label }
        let label: String
        let expect: String
        let sign: Sign
    }

    private static func uuid(_ n: Int) -> UUID {
        return UUID(uuidString: String(format: "5CA17E57-0000-4000-8000-%012ld", n)) ?? UUID()
    }

    private static func years(_ model: String, _ from: Int, _ to: Int) -> FitmentRow {
        return FitmentRow(models: [FitmentModel(name: model)], years: [YearRange(from: from, to: to)])
    }

    private static func parts(_ sign: Sign, rows: [FitmentRow]) -> Sign {
        var out = sign
        out.fitmentRows = rows
        out.syncFitmentText()
        return out
    }

    // MARK: The Library

    private static func model(_ name: String, _ short: String? = nil) -> FitmentModel {
        return FitmentModel(name: name, short: short)
    }

    /// Signs from the store's own printed sheets, added to the Library so there is
    /// something to find.
    static var librarySigns: [Sign] {
        var list: [Sign] = []

        func clearance(_ n: Int, _ name: String, _ variant: String, _ size: String,
                       _ price: String, _ was: String) {
            var sign = Sign(type: .clearance, brand: "Shoei", name: name, variant: variant, size: size,
                            price: price, regularPrice: was, percentOff: "10")
            sign.id = uuid(n)
            list.append(sign)
        }
        clearance(1, "GT-Air 3 Lilt", "", "", "1178.95", "1309.95")
        clearance(2, "Neotec 3", "Solid white", "L", "1250.95", "1389.95")
        clearance(3, "GT-Air 3", "Solid matte black", "XL", "1043.95", "1159.95")
        clearance(4, "GT-Air 3", "Solid matte black", "XXL", "1043.95", "1159.95")

        var lh = Sign(type: .used, brand: "BMW Motorrad", brandVariant: "Parts", name: "LH Aluminum Case",
                      price: "588.60", partNumber: "77411539693")
        lh.markPreOwned = true
        lh = parts(lh, rows: [
            years("R1200GSA", 2013, 2018),
            years("R1200GS", 2016, 2018),
            FitmentRow(models: [model("F850GS"), model("F850GSA", "GSA")], years: [YearRange(from: 2017, to: 2024)]),
            FitmentRow(models: [model("F900GS"), model("F900GSA", "GSA")], years: [YearRange(from: 2023, to: 2026)]),
            years("R1250GS", 2018, 2023),
            years("R1250GSA", 2018, 2024)
        ])
        lh.id = uuid(5)
        list.append(lh)

        var lv = Sign(type: .used, brand: "BMW Motorrad", brandVariant: "Parts", name: "LH Vario Case",
                      price: "807.55", partNumber: "77419899409")
        lv.markPreOwned = true
        lv = parts(lv, rows: [
            FitmentRow(models: [model("R 1250 GS"), model("R 1250 GSA", "GSA")], years: [YearRange(from: 2019, to: 2020)])
        ])
        lv.id = uuid(6)
        list.append(lv)

        var rv = Sign(type: .used, brand: "BMW Motorrad", brandVariant: "Parts", name: "RH Vario Case",
                      price: "807.55", partNumber: "77419899410")
        rv.markPreOwned = true
        rv = parts(rv, rows: [
            FitmentRow(models: [model("R 1250 GS"), model("R 1250 GSA", "GSA")], years: [YearRange(from: 2019, to: 2020)])
        ])
        rv.id = uuid(7)
        list.append(rv)

        var top = Sign(type: .used, brand: "Triumph", brandVariant: "no-text", name: "Top Box Kit",
                       price: "179.99", partNumber: "A9500955")
        top.markPreOwned = false
        top.note = "Confirm fitment with VIN"
        top.id = uuid(8)
        list.append(top)

        let now = Date()
        for i in list.indices {
            list[i].createdBy = Account.local.id
            list[i].savedAt = now
        }
        return list
    }

    // MARK: Signs to scan

    static var testSigns: [TestSign] {
        var out: [TestSign] = []

        // In the Library, unchanged. Its XXL twin is the other match.
        let a = Sign(type: .clearance, brand: "Shoei", name: "GT-Air 3", variant: "Solid matte black", size: "XL",
                     price: "1043.95", regularPrice: "1159.95", percentOff: "10")
        out.append(TestSign(
            label: "A · Same as a Library sign",
            expect: "Found, strong match. “Not this one” offers the XXL and the Lilt.",
            sign: a))

        // In the Library, with a bigger discount than when it was printed.
        let b = Sign(type: .clearance, brand: "Shoei", name: "GT-Air 3", variant: "Solid matte black", size: "XL",
                     price: "985.95", regularPrice: "1159.95", percentOff: "15")
        out.append(TestSign(
            label: "B · Library sign, discount changed",
            expect: "Found. What looks different: price $985.95 vs $1043.95, 15% vs 10%.",
            sign: b))

        // In the Library, found by part number with a new price.
        var c = Sign(type: .used, brand: "BMW Motorrad", brandVariant: "Parts", name: "LH Vario Case",
                     price: "849.99", partNumber: "77419899409")
        c.markPreOwned = true
        c = parts(c, rows: [
            FitmentRow(models: [model("R 1250 GS"), model("R 1250 GSA", "GSA")], years: [YearRange(from: 2019, to: 2020)])
        ])
        out.append(TestSign(
            label: "C · Found by part number",
            expect: "Found, strong match from the part number. The RH case is a weaker second. Price differs.",
            sign: c))

        // In the Library, sale over.
        let d = Sign(type: .regular, brand: "Shoei", name: "GT-Air 3 Lilt", price: "1309.95")
        out.append(TestSign(
            label: "D · Library sign, sale over",
            expect: "Found. What looks different: price $1309.95 vs $1178.95, type Regular vs End of season.",
            sign: d))

        // Not in the Library.
        let e = Sign(type: .regular, brand: "AGV", name: "K6 S", variant: "Matte black", size: "M", price: "649.95")
        out.append(TestSign(
            label: "E · Not in the Library: helmet",
            expect: "No close match. New sign guessed as Regular (type marked Check).",
            sign: e))

        var f = Sign(type: .used, brand: "Triumph", brandVariant: "no-text", name: "Tank pad",
                     price: "39.95", partNumber: "A9638129")
        f.markPreOwned = true
        f = parts(f, rows: [years("Speed Twin 900", 2019, 2024)])
        out.append(TestSign(
            label: "F · Not in the Library: pre-owned part",
            expect: "No close match. Guessed as a Part with fitment, pre-owned, part number read.",
            sign: f))

        let g = Sign(type: .clearance, brand: "HJC", name: "RPHA 71", variant: "Semi-flat black", size: "XL",
                     price: "479.99", regularPrice: "599.99", percentOff: "20")
        out.append(TestSign(
            label: "G · Not in the Library: end of season",
            expect: "No close match. Guessed as End of season with the was price and % off read.",
            sign: g))

        let h = Sign(type: .apparel, brand: "TCX", name: "Rush 2 Air Boots", variant: "Black", size: "10", price: "219.99")
        out.append(TestSign(
            label: "H · Not in the Library: boots",
            expect: "No close match. Guessed as Regular (apparel looks the same); switch it to Apparel.",
            sign: h))

        return out
    }

    // MARK: Signs made in Word

    /// A picture of a sign from the old Word sheets, with what the scanner should make of it.
    struct OldSign: Identifiable {
        var id: String { return file }
        let file: String
        let label: String
        let expect: String
    }

    static let oldSigns: [OldSign] = [
        OldSign(file: "OldSign-Clearance-1", label: "W1 · Clearance: GT-Air 3 Lilt",
                expect: "Name GT-AIR 3 LILT. Price 1178.95, was 1309.95, 10% off. Brand from the Shoei wordmark. Type: Sale or End of season."),
        OldSign(file: "OldSign-Clearance-3", label: "W2 · Clearance: GT-Air 3, XL",
                expect: "Price 1043.95 (cents cut off on the picture, so Check or Worked out), was 1159.95, 10%. Colour Solid matte black, size XL."),
        OldSign(file: "OldSign-Clearance-4", label: "W3 · Clearance: no price printed",
                expect: "Name, colour and size XXL read. No price: the Price field should say Check and be empty."),
        OldSign(file: "OldSign-Parts-1", label: "W4 · Parts: Triumph top box kit",
                expect: "Part number A9500955, price 179.9x. Brand Triumph worked out from the part number. Name Top Box Kit."),
        OldSign(file: "OldSign-Parts-2", label: "W5 · Parts: BMW aluminium case",
                expect: "Six fitment rows, wrapped years filled out (2023-2026). Price 588.6x. Part number may split: leftover goes in the tray."),
        OldSign(file: "OldSign-Parts-3", label: "W6 · Parts: BMW vario case, LH",
                expect: "Part number 77419899409, price 807.5x, fitment R 1250 GS 2019-2020 from the wrapped “(19-” “20)”. Brand BMW from the part number."),
        OldSign(file: "OldSign-Parts-4", label: "W7 · Parts: BMW vario case, RH",
                expect: "Part number 77419899410, price 807.5x, two fitment lines.")
    ]

    /// The picture of an old Word sign, if its file made it into the app.
    static func oldPicture(_ sign: OldSign) -> UIImage? {
        let bundle = Bundle.main
        let url = bundle.url(forResource: sign.file, withExtension: "png")
            ?? bundle.url(forResource: sign.file, withExtension: "png", subdirectory: "OldSigns")
        guard let found = url, let data = try? Data(contentsOf: found) else { return nil }
        return UIImage(data: data)
    }

    // MARK: Adding and removing

    @MainActor
    static func install(into store: Store) {
        let ids = Set(librarySigns.map { $0.id })
        store.library.removeAll { ids.contains($0.id) }
        store.library.append(contentsOf: librarySigns)
    }

    @MainActor
    static func remove(from store: Store) {
        let ids = Set(librarySigns.map { $0.id })
        store.library.removeAll { ids.contains($0.id) }
    }

    // MARK: Pictures

    /// The sign as a picture, the way a photo of the printed sign would show it.
    @MainActor
    static func picture(of sign: Sign) -> UIImage? {
        let renderer = ImageRenderer(content: SignFaceView(sign: sign).background(Color.white))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// A picture to run through the scanner without a camera.
private struct TestPicture: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Lists the test signs, with a way to save each as a picture or run it through the scanner.
struct ScanTestKitView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var picture: TestPicture?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Scan test signs")
                            .font(pt(26, .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(pt(15, .medium))
                            .foregroundColor(.ptAccent)
                    }
                    .padding(.top, 14)

                    Text("Add the sample signs to the Library first (Testing menu). Then run a sign through the scanner here, or save its picture and scan it from another screen or a printout.")
                        .font(pt(13))
                        .foregroundColor(.ptDim)
                        .padding(.top, 6)

                    VStack(spacing: 18) {
                        ForEach(ScanTestKit.testSigns) { item in
                            card(item)
                        }
                    }
                    .padding(.top, 20)

                    Text("Old Word signs")
                        .font(pt(20, .bold))
                        .foregroundColor(.white)
                        .padding(.top, 32)
                    Text("Pictures of signs from the Word sheets, to see how the scanner copes with layouts the app did not make. None of these are in the Library, so each ends on the new-sign screen.")
                        .font(pt(13))
                        .foregroundColor(.ptDim)
                        .padding(.top, 6)

                    VStack(spacing: 18) {
                        ForEach(ScanTestKit.oldSigns) { item in
                            oldCard(item)
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Color.ptBG)
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $picture) { item in
            ScanFlow(picture: item.image)
        }
        .sheet(item: $shareURL) { url in
            ActivityView(url: url)
        }
    }

    private func card(_ item: ScanTestKit.TestSign) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label)
                .font(pt(14, .semibold))
                .foregroundColor(.white)
            ScaledSign(sign: item.sign)
                .padding(10)
                .background(Color.ptInset)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.expect)
                .font(pt(12))
                .foregroundColor(.ptDim)
            HStack(spacing: 10) {
                PillButton(title: "Run through scanner", filled: true) {
                    if let image = ScanTestKit.picture(of: item.sign) {
                        picture = TestPicture(image: image)
                    }
                }
                PillButton(title: "Save picture") { save(item) }
            }
        }
    }

    private func oldCard(_ item: ScanTestKit.OldSign) -> some View {
        let image = ScanTestKit.oldPicture(item)
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.label)
                .font(pt(14, .semibold))
                .foregroundColor(.white)
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("Picture missing from the app: \(item.file).png")
                    .font(pt(12))
                    .foregroundColor(.orange)
            }
            Text(item.expect)
                .font(pt(12))
                .foregroundColor(.ptDim)
            if let image = image {
                PillButton(title: "Run through scanner", filled: true) {
                    picture = TestPicture(image: image)
                }
            }
        }
    }

    private func save(_ item: ScanTestKit.TestSign) {
        guard let image = ScanTestKit.picture(of: item.sign), let data = image.pngData() else { return }
        let name = String(item.label.prefix(1))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Test sign " + name + ".png")
        try? data.write(to: url, options: .atomic)
        shareURL = url
    }
}
#endif
