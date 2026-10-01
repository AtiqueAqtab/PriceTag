//
//  PDFExport.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-13.
//

import SwiftUI
import UIKit

@MainActor
func exportPDF(page: SignPage, signs: [Sign]) -> URL? {

    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter at 72dpi
    let margin: CGFloat = 36                                     // 0.5 inch
    let signWidth = pageRect.width - margin * 2                  // 540
    let signHeight = signWidth * SignFaceView.printSize.height / SignFaceView.printSize.width
    let gap = (pageRect.height - margin * 2 - signHeight * 4) / 3

    let safeTitle = page.title.replacingOccurrences(of: "/", with: "-")
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent(safeTitle + ".pdf")

    let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

    do {
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            for (index, sign) in signs.prefix(4).enumerated() {
                let imageRenderer = ImageRenderer(content: SignFaceView(sign: sign))
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
        return url
    } catch {
        print("PDF export failed:", error)
        return nil
    }
}

