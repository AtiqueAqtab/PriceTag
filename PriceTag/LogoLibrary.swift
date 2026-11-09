//
//  LogoLibrary.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Combine

/// Brand logos identify the maker (Arai, Shoei, Klim).
/// Feature logos are technologies that appear across makers (Gore-Tex, D3O).
enum LogoKind: String, Codable, CaseIterable, Identifiable {
    case brand
    case feature

    var id: String { return rawValue }

    var title: String {
        switch self {
        case .brand:   return "Brand logos"
        case .feature: return "Feature logos"
        }
    }

    var blurb: String {
        switch self {
        case .brand:   return "One per manufacturer. A sign carries exactly one."
        case .feature: return "Technologies shared across makers. A sign can carry several."
        }
    }
}

/// One logo image: its name, whether it's a brand or feature logo, and its version.
struct LogoAsset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: LogoKind
    var hasImage: Bool = false
    /// Optional second-level label: "Parts", "Apparel", "Racing".
    /// Several assets can share a name and differ only by this.
    var variant: String?

    var variantLabel: String { return variant ?? "" }
    var label: String { return variantLabel.isEmpty ? name : name + " · " + variantLabel }
    var fileName: String { return id.uuidString + ".png" }
}

let defaultBrandNames = [
    "Shoei", "Arai", "AGV", "REV'IT!", "Alpinestars", "Fox Racing",
    "Triumph", "BMW Motorrad", "Kawasaki", "Icon", "Klim", "Olympia",
    "Gaerne", "Joe Rocket"
]

let defaultFeatureNames = [
    "Gore-Tex", "D3O", "CE Level 2", "Waterproof", "Boa", "Heated"
]

/// Finds, trims and caches logo images from Logos.bundle.
///
/// Each logo is downsampled and cropped to its visible pixels on
/// first use, so padding in the source file doesn't shrink it on the sign.
final class LogoLibrary: ObservableObject {

    /// Views hold this directly rather than through the environment, so the same
    /// artwork is available to the PDF renderer, which has no environment.
    static let shared = LogoLibrary()

    @Published var assets: [LogoAsset] = [] {
        didSet {
            lock.lock()
            byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            nameCache = [:]
            lock.unlock()
            scheduleSave()
            if loaded && !quiet { onChange?() }
        }
    }

    /// Set while the shared Library is changing logos here, so those changes are not sent back.
    var quiet = false
    /// Called after the person changes a logo, so sync can send it.
    var onChange: (() -> Void)?

    /// Lookups happen once per logo per redraw; a linear scan of the asset list
    /// showed up in every sign that renders.
    private var byID: [UUID: LogoAsset] = [:]
    /// Guards `cache`, `nameCache` and `byID`, so artwork can be prepared on a background
    /// queue while the screen draws. Held only while a dictionary is read or written.
    private let lock = NSLock()
    private var saveTask: Task<Void, Never>?
    private var loaded = false

    private var cache: [UUID: UIImage] = [:]
    /// Every sign redraw asks for its brand and feature marks by name; this keeps
    /// that from walking the asset list each time.
    private var nameCache: [String: UIImage?] = [:]

    private var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Logos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private var indexURL: URL { return dir.appendingPathComponent("logos.json") }

    private init() {
        defer { loaded = true }
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([LogoAsset].self, from: data) {
            assets = list
        } else {
            assets = defaultBrandNames.map { LogoAsset(name: $0, kind: .brand) }
                + defaultFeatureNames.map { LogoAsset(name: $0, kind: .feature) }
        }
        syncBundledFolders()
        // Observers do not run while an initializer sets the list, so build the lookup here.
        lock.lock()
        byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lock.unlock()
    }

    /// Decodes and trims every logo on a background queue, so the first sign drawn after
    /// launch finds its artwork ready instead of decoding it while the screen waits.
    func prewarm() {
        let ids = assets.map { $0.id }
        DispatchQueue.global(qos: .utility).async { [self] in
            for id in ids { _ = image(id: id) }
        }
    }

    /// Every PNG in the app's Logos folder becomes an entry, so dropping files
    /// in is all it takes to get a new brand or feature.
    ///   Logos/Brands/Shoei.png
    ///   Logos/Brands/BMW Motorrad--Parts.png    ("--", "__" or "@" separates the version)
    ///   Logos/Features/Gore-Tex.png
    /// Builds the whole list before assigning once. Adding files one at a time
    /// re-encoded and rewrote the index for every PNG in the folder at launch.
    func syncBundledFolders() {
        LogoLibrary.scanLock.lock()
        LogoLibrary.scanCache = [:]
        LogoLibrary.scanLock.unlock()
        var next = assets
        for kind in LogoKind.allCases {
            for file in LogoLibrary.bundledFiles(kind) {
                let clean = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty { continue }
                let version = file.variant.trimmingCharacters(in: .whitespacesAndNewlines)
                let exists = next.contains {
                    $0.kind == kind
                        && $0.name.caseInsensitiveCompare(clean) == .orderedSame
                        && $0.variantLabel.caseInsensitiveCompare(version) == .orderedSame
                }
                if exists { continue }
                next.append(LogoAsset(name: clean, kind: kind, variant: version.isEmpty ? nil : version))
            }
        }
        if next.count != assets.count { assets = next }
    }

    static func folderName(_ kind: LogoKind) -> String {
        return kind == .brand ? "Logos/Brands" : "Logos/Features"
    }

    /// Walks the whole bundle rather than asking for one subdirectory, because the
    /// folder can land at different depths depending on how it was dragged into
    /// Xcode, and because Bundle.main.urls(forResourcesWithExtension:) silently
    /// skips any file whose name contains "@" — iOS reserves that for @2x/@3x.
    /// A file counts as a brand or feature by the folder it sits in, at any depth.
    private static var scanCache: [LogoKind: [(name: String, variant: String, url: URL)]] = [:]

    private static let scanLock = NSLock()

    static func bundledFiles(_ kind: LogoKind) -> [(name: String, variant: String, url: URL)] {
        scanLock.lock()
        let cached = scanCache[kind]
        scanLock.unlock()
        if let hit = cached { return hit }
        var out: [(name: String, variant: String, url: URL)] = []
        let wanted = kind == .brand ? "brands" : "features"
        let allowed: Set<String> = ["png", "jpg", "jpeg"]
        var found: [URL] = []
        var roots: [URL] = []
        if let bundle = Bundle.main.resourceURL { roots.append(bundle) }
        roots.append(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                guard allowed.contains(url.pathExtension.lowercased()) else { continue }
                let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
                if parent == wanted {
                    found.append(url)
                } else if kindPrefix(url) == kind {
                    found.append(url)
                }
            }
        }
        for url in found.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let (name, variant) = splitVersion(url.deletingPathExtension().lastPathComponent)
            if name.isEmpty { continue }
            out.append((name, variant, url))
        }
        scanLock.lock()
        scanCache[kind] = out
        scanLock.unlock()
        return out
    }

    /// One line per file the app can see — shown at the bottom of the Logos tab so a
    /// missing logo is a folder problem you can read rather than guess at.
    static func scanReport() -> String {
        var lines: [String] = []
        var any = false
        for kind in LogoKind.allCases {
            let files = bundledFiles(kind)
            let label = kind == .brand ? "Brands" : "Features"
            lines.append(label + ": " + String(files.count) + " file" + (files.count == 1 ? "" : "s"))
            for file in files {
                any = true
                lines.append("  " + file.name + (file.variant.isEmpty ? "" : " · " + file.variant))
            }
        }
        if !any {
            lines.append("")
            lines.append("No logos found. Name the folder Logos.bundle with")
            lines.append("Brands and Features inside it.")
            lines.append("Top level of the app bundle:")
            if let root = Bundle.main.resourceURL {
                let items = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
                let shown = items.filter { !$0.hasSuffix(".nib") && !$0.hasSuffix(".car") }.sorted()
                if shown.isEmpty {
                    lines.append("  (empty)")
                } else {
                    for item in shown.prefix(24) { lines.append("  " + item) }
                    if shown.count > 24 { lines.append("  … and " + String(shown.count - 24) + " more") }
                }
            }
            lines.append("")
            lines.append("Documents folder:")
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let items = ((try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []).sorted()
            for item in items.prefix(12) { lines.append("  " + item) }
            if items.isEmpty { lines.append("  (empty)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Xcode 16 synchronized folders copy images in flattened, so the Brands and
    /// Features subfolders do not survive into the bundle. A "Brand-" or "Feature-"
    /// prefix on the filename carries the same information and does survive.
    static func kindPrefix(_ url: URL) -> LogoKind? {
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        for separator in ["-", " ", "_"] {
            if base.hasPrefix("brand" + separator) { return .brand }
            if base.hasPrefix("feature" + separator) { return .feature }
        }
        return nil
    }

    /// Drops a leading "Brand-" / "Feature-" so the sign shows "Shoei", not "Brand-Shoei".
    static func stripKindPrefix(_ base: String) -> String {
        for word in ["brand", "feature"] {
            for separator in ["-", " ", "_"] {
                let prefix = word + separator
                if base.lowercased().hasPrefix(prefix) {
                    return String(base.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return base
    }

    static func splitVersion(_ base: String) -> (String, String) {
        let clean = stripKindPrefix(base)
        for separator in ["--", "__", "@"] where clean.contains(separator) {
            let parts = clean.components(separatedBy: separator)
            return (
                parts[0].trimmingCharacters(in: .whitespaces),
                parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespaces)
            )
        }
        return (clean.trimmingCharacters(in: .whitespaces), "")
    }

    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        let snapshot = assets
        let url = indexURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Called when the app leaves the foreground, so a debounced write is not lost.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let data = try? JSONEncoder().encode(assets) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Reading

    func list(_ kind: LogoKind) -> [LogoAsset] {
        return assets.filter { $0.kind == kind }
    }

    /// One entry per brand, even when that brand has several versions of its mark.
    func names(_ kind: LogoKind) -> [String] {
        var out: [String] = []
        for asset in list(kind) where !out.contains(asset.name) { out.append(asset.name) }
        return out
    }

    /// Every version filed under one name, in the order they were added.
    func versions(of name: String, kind: LogoKind) -> [LogoAsset] {
        return list(kind).filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func variantLabels(of name: String, kind: LogoKind) -> [String] {
        return versions(of: name, kind: kind).map { $0.variantLabel }
    }

    func asset(named name: String, kind: LogoKind, variant: String = "") -> LogoAsset? {
        let matches = versions(of: name, kind: kind)
        if !variant.isEmpty,
           let hit = matches.first(where: { $0.variantLabel.caseInsensitiveCompare(variant) == .orderedSame }) {
            return hit
        }
        return matches.first
    }

    func image(id: UUID) -> UIImage? {
        lock.lock()
        let hit = cache[id]
        var known = byID[id]
        lock.unlock()
        if let hit = hit { return hit }
        // Only the main thread may read the asset list; the lookup above covers the rest.
        if known == nil && Thread.isMainThread { known = assets.first(where: { $0.id == id }) }
        guard let asset = known else { return nil }

        var result: UIImage? = nil
        if asset.hasImage,
           let image = LogoLibrary.downsampled(dir.appendingPathComponent(asset.fileName)) {
            result = LogoLibrary.trimmed(image)
        } else if let bundled = LogoLibrary.bundledImage(named: asset.name, variant: asset.variantLabel) {
            result = LogoLibrary.trimmed(bundled)
        }
        if let result = result {
            lock.lock()
            cache[id] = result
            lock.unlock()
        }
        return result
    }

    /// A PNG exported with padding around the mark wastes the sign's logo box.
    /// Cropping to the opaque pixels lets the same slot draw the mark larger.
    /// Runs once per logo, on the downsampled copy, and the result is cached.
    static func trimmed(_ image: UIImage, threshold: UInt8 = 8) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width
        let h = cg.height
        guard w > 1, h > 1 else { return image }

        var alpha = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: w,
                      height: h,
                      bitsPerComponent: 8,
                      bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                  ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return image }

        var minX = w, minY = h, maxX = -1, maxY = -1
        alpha.withUnsafeBufferPointer { px in
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where px[row + x] > threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // Fully transparent, or already tight to the edges.
        guard maxX >= minX, maxY >= minY else { return image }
        if minX == 0 && minY == 0 && maxX == w - 1 && maxY == h - 1 { return image }

        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Logos print at most 190pt wide but the source files are full-resolution.
    /// Decoding a thumbnail keeps memory and draw cost proportional to what is shown.
    static func downsampled(_ url: URL, maxPixel: CGFloat = 900) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            return UIImage(contentsOfFile: url.path)
        }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(cgImage: cg)
    }

    /// True when the sign will print real artwork rather than the labelled box.
    func hasArtwork(id: UUID) -> Bool {
        return image(id: id) != nil
    }

    /// Looks for artwork shipped with the app, so common brands work on first launch.
    /// "Gore-Tex" matches an image set called "Gore-Tex", "gore-tex" or "logo-gore-tex".
    /// "Shoei" with variant "Parts" also matches "Shoei Parts" and "shoei-parts" first.
    static func bundledImage(named name: String, variant: String = "") -> UIImage? {
        var candidates: [String] = []
        if !variant.isEmpty {
            candidates += [
                name + "-" + variant,
                name + " " + variant,
                name + "_" + variant,
                slugify(name + "-" + variant),
                "logo-" + slugify(name + "-" + variant)
            ]
        }
        candidates += [name, slugify(name), "logo-" + slugify(name)]
        for candidate in candidates {
            if let image = UIImage(named: candidate) { return image }
        }
        return bundledFileImage(named: name, variant: variant)
    }

    /// Falls back to the loose PNGs in the bundle's Logos folder.
    static func bundledFileImage(named name: String, variant: String) -> UIImage? {
        for kind in LogoKind.allCases {
            let files = bundledFiles(kind)
            let sameName = files.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if sameName.isEmpty { continue }
            if !variant.isEmpty,
               let hit = sameName.first(where: { $0.variant.caseInsensitiveCompare(variant) == .orderedSame }),
               let image = downsampled(hit.url) {
                return image
            }
            if let first = sameName.first, let image = downsampled(first.url) {
                return image
            }
        }
        return nil
    }

    static func slugify(_ text: String) -> String {
        return text.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    func image(named name: String, kind: LogoKind, variant: String = "") -> UIImage? {
        let key = kind.rawValue + "|" + name.lowercased() + "|" + variant.lowercased()
        lock.lock()
        let hit = nameCache[key]
        lock.unlock()
        if let hit = hit { return hit }
        guard let asset = asset(named: name, kind: kind, variant: variant) else {
            lock.lock()
            nameCache.updateValue(nil, forKey: key)
            lock.unlock()
            return nil
        }
        let found = image(id: asset.id)
        lock.lock()
        nameCache[key] = found
        lock.unlock()
        return found
    }

    // MARK: - Library file

    /// Logos whose artwork was added or replaced on this phone, for the Library file.
    /// Artwork that ships inside the app is left out; every phone already has it.
    func exportableLogos() -> [LibraryFile.LogoEntry] {
        var out: [LibraryFile.LogoEntry] = []
        for asset in assets where asset.hasImage {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(asset.fileName)) else { continue }
            out.append(LibraryFile.LogoEntry(name: asset.name, kind: asset.kind, variant: asset.variant, png: data))
        }
        return out
    }

    // MARK: - Shared Library

    func asset(id: UUID) -> LogoAsset? {
        return assets.first { $0.id == id }
    }

    /// The logo with exactly this kind, name and version label, ignoring capitals.
    func existing(kind: LogoKind, name: String, variant: String) -> LogoAsset? {
        return assets.first {
            $0.kind == kind
                && $0.name.caseInsensitiveCompare(name) == .orderedSame
                && $0.variantLabel.caseInsensitiveCompare(variant) == .orderedSame
        }
    }

    /// The artwork picture saved for a logo, if it has its own (not one shipped in the app).
    func artworkData(id: UUID) -> Data? {
        guard let asset = asset(id: id), asset.hasImage else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(asset.fileName))
    }

    /// A cheap stand-in for "has the artwork changed": file size and time. Empty when the
    /// logo has no artwork of its own.
    func artworkStamp(id: UUID) -> String {
        guard let asset = asset(id: id), asset.hasImage else { return "" }
        let path = dir.appendingPathComponent(asset.fileName).path
        guard let info = try? FileManager.default.attributesOfItem(atPath: path) else { return "" }
        let size = (info[.size] as? NSNumber)?.intValue ?? 0
        let time = (info[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return String(size) + ":" + String(Int(time * 1000))
    }

    /// Makes this logo's name and kind match the shared one, adding the logo if it is new.
    func applyShared(id: UUID, kind: LogoKind, name: String, variant: String) {
        let version: String? = variant.isEmpty ? nil : variant
        if let i = assets.firstIndex(where: { $0.id == id }) {
            assets[i].kind = kind
            assets[i].name = name
            assets[i].variant = version
        } else {
            assets.append(LogoAsset(id: id, name: name, kind: kind, variant: version))
        }
        lock.lock()
        cache[id] = nil
        lock.unlock()
    }

    // MARK: - Writing

    @discardableResult
    func add(name: String, kind: LogoKind, variant: String = "") -> LogoAsset? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }
        let version = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = versions(of: clean, kind: kind).first(where: {
            $0.variantLabel.caseInsensitiveCompare(version) == .orderedSame
        }) { return existing }
        let asset = LogoAsset(name: clean, kind: kind, variant: version.isEmpty ? nil : version)
        assets.append(asset)
        return asset
    }

    func setVariant(_ id: UUID, to variant: String) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        let clean = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        assets[i].variant = clean.isEmpty ? nil : clean
        lock.lock()
        cache[id] = nil
        lock.unlock()
    }

    func rename(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[i].name = clean
    }

    /// Stores a copy as PNG, capped at 600px on the long edge so the PDF stays small.
    func setImage(_ image: UIImage, for id: UUID) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        let scaled = LogoLibrary.downscale(image, longEdge: 600)
        guard let data = scaled.pngData() else { return }
        try? data.write(to: dir.appendingPathComponent(assets[i].fileName), options: .atomic)
        lock.lock()
        cache[id] = scaled
        lock.unlock()
        assets[i].hasImage = true
    }

    /// False when the data is not a picture iOS can decode (SVG, for one).
    @discardableResult
    func setImage(data: Data, for id: UUID) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        setImage(image, for: id)
        return true
    }

    /// Reads an image off the system clipboard — the copy-paste path.
    @discardableResult
    func pasteImage(for id: UUID) -> Bool {
        let board = UIPasteboard.general
        if let image = board.image {
            setImage(image, for: id)
            return true
        }
        if let data = board.data(forPasteboardType: "public.png") ?? board.data(forPasteboardType: "public.jpeg"),
           let image = UIImage(data: data) {
            setImage(image, for: id)
            return true
        }
        return false
    }

    func clearImage(for id: UUID) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(assets[i].fileName))
        lock.lock()
        cache[id] = nil
        lock.unlock()
        assets[i].hasImage = false
    }

    func remove(_ id: UUID) {
        clearImage(for: id)
        assets.removeAll { $0.id == id }
    }

    private static func downscale(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        if longest <= longEdge || longest == 0 { return image }
        let factor = longEdge / longest
        let size = CGSize(width: w * factor, height: h * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
