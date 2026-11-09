//
//  SignStraightener.swift
//  PriceTag
//
//  Finds the printed sign's border in a photo, flattens it into a straight-on picture,
//  and reads the text from that. Photos taken at an angle, or with a desk and other
//  paper around the sign, read far better this way. Everything happens on the phone.
//

import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// A photo made ready for reading: what was read, and the picture it was read from.
nonisolated struct PreparedScan {
    var image: UIImage
    var items: [ScanItem]
    /// True when the sign's border was found and the picture is the sign alone.
    var straightened: Bool
}

nonisolated enum SignStraightener {

    /// Straightens the photo when it can find the sign, reads it, and turns it a quarter
    /// or half turn if the first reading finds almost nothing.
    static func prepare(_ photo: UIImage) async -> PreparedScan {
        let flat = await straighten(photo)
        let base = flat ?? LogoMatcher.upright(photo, maxSide: 2000)
        var bestImage = base
        var bestItems = await TextReader.read(base)

        if characters(in: bestItems) < 15, let cg = base.cgImage {
            let turns: [UIImage.Orientation] = base.size.width >= base.size.height ? [.down] : [.right, .left]
            for turn in turns {
                let turned = UIImage(cgImage: cg, scale: 1, orientation: turn)
                let items = await TextReader.read(turned)
                if characters(in: items) > characters(in: bestItems) {
                    bestImage = turned
                    bestItems = items
                }
            }
        }
        return PreparedScan(image: bestImage, items: bestItems, straightened: flat != nil)
    }

    private static func characters(in items: [ScanItem]) -> Int {
        return items.reduce(0) { $0 + ScanText.squash($1.text).count }
    }

    /// The sign alone and flat, or nil when no border that looks like a sign was found.
    static func straighten(_ photo: UIImage) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: straightenNow(photo))
            }
        }
    }

    private static func straightenNow(_ photo: UIImage) -> UIImage? {
        let base = LogoMatcher.upright(photo, maxSide: 2000)
        guard let cg = base.cgImage, let corners = findSign(in: cg) else { return nil }
        return flatten(cg, corners: corners)
    }

    // MARK: Finding the border

    /// The corners of the biggest sign-shaped rectangle: top left, top right, bottom right,
    /// bottom left, in pixels measured from the bottom left like Core Image does.
    private static func findSign(in cg: CGImage) -> [CGPoint]? {
        let request = VNDetectRectanglesRequest()
        // Signs are about three times as wide as tall; a sheet of paper is not.
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 0.55
        request.minimumSize = 0.2
        request.minimumConfidence = 0.5
        request.maximumObservations = 8
        request.quadratureTolerance = 25
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        var best: (area: CGFloat, corners: [CGPoint])?
        for found in request.results ?? [] {
            let tl = CGPoint(x: found.topLeft.x * w, y: found.topLeft.y * h)
            let tr = CGPoint(x: found.topRight.x * w, y: found.topRight.y * h)
            let br = CGPoint(x: found.bottomRight.x * w, y: found.bottomRight.y * h)
            let bl = CGPoint(x: found.bottomLeft.x * w, y: found.bottomLeft.y * h)
            let across = (distance(tl, tr) + distance(bl, br)) / 2
            let down = (distance(tl, bl) + distance(tr, br)) / 2
            let longSide = max(across, down)
            let shortSide = min(across, down)
            if longSide <= 0 { continue }
            let ratio = shortSide / longSide
            if ratio < 0.22 || ratio > 0.5 { continue }
            let area = across * down
            if area < w * h * 0.15 { continue }
            if best == nil || area > best!.area {
                best = (area, [tl, tr, br, bl])
            }
        }
        return best?.corners
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: Flattening

    private static func flatten(_ cg: CGImage, corners: [CGPoint]) -> UIImage? {
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: cg)
        filter.topLeft = corners[0]
        filter.topRight = corners[1]
        filter.bottomRight = corners[2]
        filter.bottomLeft = corners[3]
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let flat = context.createCGImage(output, from: output.extent) else { return nil }
        return LogoMatcher.upright(UIImage(cgImage: flat), maxSide: 2000)
    }
}
