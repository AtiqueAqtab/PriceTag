//
//  LogoMatcher.swift
//  PriceTag
//
//  Finds which brand logo from the Logos library shows up in a photo of a sign.
//  Everything happens on the phone.
//

import UIKit
import Vision

/// A brand logo that looks like something in the photo.
nonisolated struct LogoCandidate: Identifiable, Hashable {
    var name: String
    /// The version of the brand's mark, or empty when the brand has only one.
    var variant: String
    /// Lower is closer.
    var distance: Float

    var id: String { return name + "@" + variant }
}

/// The closest logos, and whether the best one is clear enough to use without asking.
nonisolated struct LogoMatch {
    /// Best first, one per brand, at most three.
    var candidates: [LogoCandidate] = []
    var confident = false
    /// The distances, for checking how well the matching does.
    var debug = ""
}

/// A logo from the library, ready to compare.
nonisolated struct LogoInput {
    var id: String
    var name: String
    var variant: String
    var hasVariants: Bool
    var image: UIImage
}

nonisolated enum LogoMatcher {

    /// How close the best logo has to be, and how much closer than the runner-up.
    /// These are first guesses; the numbers shown in test builds are for tuning them.
    static let absoluteMax: Float = 1.0
    static let relativeMargin: Float = 0.85

    private nonisolated(unsafe) static var cache: [String: VNFeaturePrintObservation] = [:]
    private static let lock = NSLock()

    // MARK: Entry points (from the main thread)

    /// Compares the photo with every brand logo in the library.
    @MainActor
    static func match(photo: UIImage) async -> LogoMatch {
        let logos = gather()
        return await run(photo: photo, logos: logos)
    }

    /// Prepares the library's logos ahead of time so the first scan is not slower.
    @MainActor
    static func warmUp() async {
        let logos = gather()
        await prepare(logos)
    }

    @MainActor
    private static func gather() -> [LogoInput] {
        let assets = LogoLibrary.shared.list(.brand)
        var out: [LogoInput] = []
        for asset in assets {
            guard let image = LogoLibrary.shared.image(id: asset.id) else { continue }
            let siblings = assets.filter { $0.name.caseInsensitiveCompare(asset.name) == .orderedSame }.count
            out.append(LogoInput(id: asset.id.uuidString, name: asset.name, variant: asset.variantLabel,
                                 hasVariants: siblings > 1, image: image))
        }
        return out
    }

    // MARK: Off the main thread

    private static func run(photo: UIImage, logos: [LogoInput]) async -> LogoMatch {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runNow(photo: photo, logos: logos))
            }
        }
    }

    private static func prepare(_ logos: [LogoInput]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                _ = prints(for: logos)
                continuation.resume()
            }
        }
    }

    private static func runNow(photo: UIImage, logos: [LogoInput]) -> LogoMatch {
        let deadline = Date().addingTimeInterval(7)
        let library = prints(for: logos)
        if library.isEmpty { return LogoMatch() }
        let base = upright(photo, maxSide: 1400)
        guard let cg = base.cgImage else { return LogoMatch() }

        var best: [Int: Float] = [:]
        for rect in candidateRects(for: cg) {
            if Date() > deadline { break }
            guard let piece = crop(cg, to: rect), let found = featurePrint(UIImage(cgImage: piece)) else { continue }
            for (i, entry) in library.enumerated() {
                var distance: Float = 0
                do {
                    try found.computeDistance(&distance, to: entry.print)
                } catch {
                    continue
                }
                if let old = best[i], old <= distance { continue }
                best[i] = distance
            }
        }
        return summarise(best, library)
    }

    private static func summarise(_ best: [Int: Float],
                                  _ library: [(input: LogoInput, print: VNFeaturePrintObservation)]) -> LogoMatch {
        var byName: [String: LogoCandidate] = [:]
        for (i, distance) in best {
            let input = library[i].input
            if let old = byName[input.name], old.distance <= distance { continue }
            byName[input.name] = LogoCandidate(name: input.name,
                                               variant: input.hasVariants ? input.variant : "",
                                               distance: distance)
        }
        let ranked = byName.values.sorted { $0.distance < $1.distance }
        var match = LogoMatch()
        match.candidates = Array(ranked.prefix(3))
        if let top = ranked.first {
            let next = ranked.count > 1 ? ranked[1].distance : Float.greatestFiniteMagnitude
            match.confident = top.distance <= absoluteMax && top.distance <= next * relativeMargin
        }
        match.debug = ranked.prefix(6)
            .map { $0.name + " " + String(format: "%.2f", $0.distance) }
            .joined(separator: " · ")
        return match
    }

    // MARK: Feature prints

    private static func prints(for logos: [LogoInput]) -> [(input: LogoInput, print: VNFeaturePrintObservation)] {
        var out: [(input: LogoInput, print: VNFeaturePrintObservation)] = []
        for logo in logos {
            let w = Int(logo.image.size.width * logo.image.scale)
            let h = Int(logo.image.size.height * logo.image.scale)
            let key = logo.id + "|" + String(w) + "x" + String(h)
            lock.lock()
            let hit = cache[key]
            lock.unlock()
            if let found = hit {
                out.append((logo, found))
                continue
            }
            guard let made = featurePrint(logo.image) else { continue }
            lock.lock()
            cache[key] = made
            lock.unlock()
            out.append((logo, made))
        }
        return out
    }

    /// A numeric summary of how a picture looks. Pictures that look alike have a small distance.
    private static func featurePrint(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let cg = square(image) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first
    }

    /// The picture fitted onto a white square, so logos and photo pieces compare alike.
    private static func square(_ image: UIImage) -> CGImage? {
        let side: CGFloat = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let drawn = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let w = image.size.width
            let h = image.size.height
            if w <= 0 || h <= 0 { return }
            let fit = min(side * 0.9 / w, side * 0.9 / h)
            let size = CGSize(width: w * fit, height: h * fit)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        return drawn.cgImage
    }

    // MARK: Where to look in the photo

    /// The photo, turned the right way up and no bigger than `maxSide`.
    static func upright(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        if longest <= 0 { return image }
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Pieces of the photo that might hold a logo, as fractions of the photo, top left origin.
    /// First whatever the phone thinks stands out, then windows of a few sizes over the
    /// parts of the photo that have ink in them rather than blank paper.
    private static func candidateRects(for cg: CGImage) -> [CGRect] {
        var rects: [CGRect] = salientRects(for: cg)
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let columns = 80
        let rows = max(8, Int((80 * height / width).rounded()))
        guard let ink = inkMap(cg, columns: columns, rows: rows) else { return rects }

        var windows: [(rect: CGRect, share: Double)] = []
        for fraction in [0.2, 0.3, 0.42] as [CGFloat] {
            for aspect in [1.0, 2.4] as [CGFloat] {
                let w = fraction
                let h = fraction * width / aspect / height
                if h > 1 { continue }
                var y: CGFloat = 0
                while y <= 1 - h + 0.001 {
                    var x: CGFloat = 0
                    while x <= 1 - w + 0.001 {
                        let share = inkShare(ink, columns: columns, rows: rows, x: x, y: y, w: w, h: h)
                        if share >= 0.05 && share <= 0.8 {
                            windows.append((CGRect(x: x, y: y, width: w, height: h), share))
                        }
                        x += w * 0.5
                    }
                    y += h * 0.5
                }
            }
        }
        // Logos are mostly marks with some white around them.
        windows.sort { abs($0.share - 0.3) < abs($1.share - 0.3) }
        rects.append(contentsOf: windows.prefix(28).map { $0.rect })
        return rects
    }

    /// Up to three areas Vision finds eye-catching, widened a little.
    private static func salientRects(for cg: CGImage) -> [CGRect] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        var out: [CGRect] = []
        for observation in request.results ?? [] {
            for object in observation.salientObjects ?? [] {
                let b = object.boundingBox
                // Vision measures from the bottom left.
                var rect = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                rect = rect.insetBy(dx: -rect.width * 0.08, dy: -rect.height * 0.08)
                rect = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                if rect.width > 0.05 && rect.height > 0.03 { out.append(rect) }
            }
        }
        return Array(out.prefix(3))
    }

    /// A small grid saying where the photo is not blank paper.
    private static func inkMap(_ cg: CGImage, columns: Int, rows: Int) -> [Bool]? {
        var pixels = [UInt8](repeating: 255, count: columns * rows)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        if !drawn { return nil }
        return pixels.map { $0 < 170 }
    }

    private static func inkShare(_ ink: [Bool], columns: Int, rows: Int,
                                 x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> Double {
        let x0 = Int(x * CGFloat(columns))
        let x1 = min(columns, Int(((x + w) * CGFloat(columns)).rounded(.up)))
        let y0 = Int(y * CGFloat(rows))
        let y1 = min(rows, Int(((y + h) * CGFloat(rows)).rounded(.up)))
        var inked = 0
        var total = 0
        for row in y0..<max(y0, y1) {
            for column in x0..<max(x0, x1) {
                total += 1
                if ink[row * columns + column] { inked += 1 }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
    }

    private static func crop(_ cg: CGImage, to rect: CGRect) -> CGImage? {
        let pixels = CGRect(x: rect.minX * CGFloat(cg.width), y: rect.minY * CGFloat(cg.height),
                            width: rect.width * CGFloat(cg.width), height: rect.height * CGFloat(cg.height)).integral
        return cg.cropping(to: pixels)
    }
}
