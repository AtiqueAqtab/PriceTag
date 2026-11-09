//
//  PDFExport.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-13.
//

import SwiftUI
import UIKit

/// What to do with the empty slots on a sheet that has fewer than four signs.
enum EmptySlots: String, CaseIterable, Identifiable {
    /// Fill the sheet with copies of the signs it already has.
    case repeatToFill
    /// Leave the empty slots empty.
    case blank
    /// Run the signs from all chosen pages on into each other, four to a sheet.
    case pack

    var id: String { return rawValue }

    var title: String {
        switch self {
        case .repeatToFill: return "Repeat to fill"
        case .blank:        return "Leave blank"
        case .pack:         return "Pack"
        }
    }
}

extension SignPage {
    /// A page prints as many sheets as its signs need: four standard signs to a sheet, or
    /// two landscape signs.
    var sheetCount: Int {
        return sheets.count
    }

    /// True when some sheet of this page has empty slots.
    var hasPartialSheet: Bool {
        return sheets.contains { $0.count < sheetCapacity($0) }
    }
}

/// How many signs the sheet holding `chunk` takes: two when it is landscape, otherwise four.
func sheetCapacity(_ chunk: [Sign]) -> Int {
    return chunk.first?.onLandscapeSheet == true ? 2 : 4
}

/// Splits signs into sheets, in order. A run of landscape signs takes two to a sheet, a run
/// of standard signs four, and a sheet never mixes the two.
func sheetChunks(_ signs: [Sign]) -> [[Sign]] {
    var out: [[Sign]] = []
    var current: [Sign] = []
    for sign in signs {
        if let first = current.first {
            let mixed = first.onLandscapeSheet != sign.onLandscapeSheet
            if mixed || current.count == sheetCapacity(current) {
                out.append(current)
                current = []
            }
        }
        current.append(sign)
    }
    if !current.isEmpty { out.append(current) }
    return out
}

/// The slots of a sheet that holds `chunk`. Empty slots repeat the sheet's own
/// signs or stay empty, depending on `fill`.
func sheetSlots(_ chunk: [Sign], fill: EmptySlots) -> [Sign?] {
    let per = sheetCapacity(chunk)
    if fill == .repeatToFill && !chunk.isEmpty {
        return (0..<per).map { Optional(chunk[$0 % chunk.count]) }
    }
    var slots: [Sign?] = chunk
    while slots.count < per { slots.append(nil) }
    return slots
}

/// A landscape sheet has two slots; a standard one has four.
func isLandscapeSheet(_ slots: [Sign?]) -> Bool {
    return slots.count == 2
}

/// Works out what prints on every sheet, in order. A nil slot is left empty.
///
/// - Parameter skipping: For each page, the sheets (counted from 0) to leave out.
///   Packing happens after they are left out, so the signs after them move up.
func printSheets(_ pages: [SignPage], fill: EmptySlots, skipping: [UUID: Set<Int>] = [:]) -> [[Sign?]] {
    func kept(_ page: SignPage) -> [[Sign]] {
        let skip = skipping[page.id] ?? []
        return page.sheets.enumerated()
            .filter { !skip.contains($0.offset) }
            .map { $0.element }
    }

    if fill == .pack {
        // Signs run on into each other; landscape and standard signs still get sheets of their own.
        let signs = pages.flatMap { page in kept(page).flatMap { $0 } }
        return sheetChunks(signs).map { sheetSlots($0, fill: .blank) }
    }
    var sheets: [[Sign?]] = []
    for page in pages {
        for chunk in kept(page) {
            sheets.append(sheetSlots(chunk, fill: fill))
        }
    }
    return sheets
}

/// The file name for an export: the page's title, or the date when several pages go in one file.
func exportTitle(_ pages: [SignPage]) -> String {
    if pages.count == 1 { return pages[0].title }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return "PriceTags " + formatter.string(from: Date())
}

/// Draws sheets of signs onto US Letter PDF pages, one PDF page per sheet. A sheet of
/// two signs is a sideways page.
///
/// - Parameters:
///   - title: Becomes the file name.
///   - sheets: What prints on each sheet, top to bottom. A nil slot stays empty.
/// - Returns: A URL to the PDF in the temporary folder, or `nil` if there is nothing to print or writing failed.
@MainActor
func exportPDF(title: String, sheets: [[Sign?]]) -> URL? {
    if sheets.isEmpty { return nil }

    let portrait = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter at 72dpi
    let sideways = CGRect(x: 0, y: 0, width: 792, height: 612)
    let margin: CGFloat = 36                                     // 0.5 inch

    let safeTitle = title
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent(safeTitle + ".pdf")

    let renderer = UIGraphicsPDFRenderer(bounds: portrait)

    do {
        try renderer.writePDF(to: url) { context in
            for sheet in sheets {
                let landscape = isLandscapeSheet(sheet)
                let pageRect = landscape ? sideways : portrait
                let perSheet = landscape ? 2 : 4
                let faceHeight = SignFaceView.printSize.height + (landscape ? SignFaceView.landscapeExtra : 0)
                let signWidth = pageRect.width - margin * 2
                let signHeight = signWidth * faceHeight / SignFaceView.printSize.width
                let gap = (pageRect.height - margin * 2 - signHeight * CGFloat(perSheet)) / CGFloat(perSheet - 1)

                context.beginPage(withBounds: pageRect, pageInfo: [:])
                for (index, slot) in sheet.prefix(perSheet).enumerated() {
                    guard let sign = slot else { continue }
                    let imageRenderer = ImageRenderer(content: SignFaceView(sign: sign, landscape: landscape))
                    imageRenderer.render { size, renderInContext in
                        let cg = context.cgContext
                        cg.saveGState()
                        let top = margin + CGFloat(index) * (signHeight + gap)
                        // PDF contexts are y-down; flip so the view draws upright.
                        cg.translateBy(x: margin, y: top + signHeight)
                        cg.scaleBy(
                            x: signWidth / size.width,
                            y: -signHeight / size.height
                        )
                        renderInContext(cg)
                        cg.restoreGState()
                    }
                }
            }
        }
        return url
    } catch {
        print("PDF export failed:", error)
        return nil
    }
}
