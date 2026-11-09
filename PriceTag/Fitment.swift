//
//  Fitment.swift
//  PriceTag
//
//  What a part fits, and how that prints as tags along the bottom of a Parts sign.
//

import SwiftUI
import UIKit

/// One model a part fits.
struct FitmentModel: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    /// What prints instead of the full name when this model shares a tag with others,
    /// so "R 1250 GS / R 1250 GS Adventure" can print as "R 1250 GS / GSA".
    var short: String?

    /// The short name when there is one, otherwise the full name.
    var printedShort: String {
        let s = (short ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }
}

/// A span of model years. Either end can be left empty while typing.
struct YearRange: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var from: Int?
    var to: Int?

    var isEmpty: Bool { return from == nil && to == nil }

    /// "2019–2024", a single year, "2019+" or "to 2019".
    var text: String {
        switch (from, to) {
        case let (a?, b?):
            let x = YearRange.normalized(a)
            let y = YearRange.normalized(b)
            return x == y ? "\(x)" : "\(min(x, y))–\(max(x, y))"
        case let (a?, nil): return "\(YearRange.normalized(a))+"
        case let (nil, b?): return "to \(YearRange.normalized(b))"
        default: return ""
        }
    }

    static func format(_ ranges: [YearRange]) -> String {
        return ranges.map { $0.text }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Two digits mean 20xx up to 50 and 19xx after that, so "19" prints as 2019.
    static func normalized(_ value: Int) -> Int {
        if value >= 100 { return value }
        return value <= 50 ? 2000 + value : 1900 + value
    }
}

/// One row of the fitment list: these models, in these years. It prints as one tag.
struct FitmentRow: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var models: [FitmentModel] = []
    var years: [YearRange] = [YearRange()]

    /// What this row prints, or nil when it has nothing to print yet.
    var tag: FitTag? {
        let named = models.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let yearText = YearRange.format(years)
        if named.isEmpty && yearText.isEmpty { return nil }
        let names: [String]
        if named.count > 1 {
            names = named.map { $0.printedShort }
        } else {
            names = named.map { $0.name }
        }
        return FitTag(models: names.joined(separator: " / "), years: yearText)
    }
}

/// One printed tag: the models in bold, then the years.
struct FitTag: Hashable {
    var models: String
    var years: String
}

extension Sign {
    /// The tags this sign prints. Signs saved before fitment had rows print each of
    /// their old lines as a tag, so nothing is lost.
    var fitTags: [FitTag] {
        if universalFit == true { return [FitTag(models: "ALL MODELS", years: "")] }
        if let rows = fitmentRows { return rows.compactMap { $0.tag } }
        return fitment
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { FitTag(models: $0, years: "") }
    }

    var hasFitment: Bool { return !fitTags.isEmpty }

    /// Turns old fitment lines into rows, one per line, with the whole line as the model.
    /// Does nothing for a sign that already has rows.
    mutating func adoptFitmentRows() {
        if fitmentRows != nil { return }
        fitmentRows = fitment
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { FitmentRow(models: [FitmentModel(name: $0)], years: []) }
    }

    /// Keeps the plain-text `fitment` lines (used by search) in step with the rows.
    mutating func syncFitmentText() {
        guard let rows = fitmentRows else { return }
        fitment = rows.compactMap { $0.tag }.map { tag in
            tag.years.isEmpty ? tag.models : tag.models + " " + tag.years
        }
    }
}

/// Reads a pasted list such as "2019-2024 R 1250 GS / GSA" into rows.
enum FitmentParser {
    static func rows(from text: String) -> [FitmentRow] {
        var rows: [FitmentRow] = []
        var keys: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let (years, rest) = extractYears(line)
            let names = rest
                .replacingOccurrences(of: "&", with: "/")
                .components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—()")) }
                .filter { !$0.isEmpty }
            if names.isEmpty && years.isEmpty { continue }
            let key = YearRange.format(years)
            // Lines with the same years share a row.
            if !key.isEmpty, let at = keys.firstIndex(of: key) {
                rows[at].models.append(contentsOf: names.map { FitmentModel(name: $0) })
                continue
            }
            keys.append(key)
            rows.append(FitmentRow(models: names.map { FitmentModel(name: $0) },
                                   years: years.isEmpty ? [YearRange()] : years))
        }
        return rows
    }

    /// Pulls years such as 2019, 2019-2024 or 2019 to 2024 out of a line.
    private static func extractYears(_ line: String) -> ([YearRange], String) {
        let pattern = "\\b((?:19|20)\\d{2})(?:\\s*(?:-|–|—|to)\\s*((?:19|20)\\d{2}))?\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return ([], line) }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var ranges: [YearRange] = []
        let rest = NSMutableString(string: line)
        for m in matches {
            let from = Int(ns.substring(with: m.range(at: 1)))
            var to = from
            if m.range(at: 2).location != NSNotFound {
                to = Int(ns.substring(with: m.range(at: 2)))
            }
            ranges.append(YearRange(from: from, to: to))
        }
        for m in matches.reversed() {
            rest.replaceCharacters(in: m.range, with: " ")
        }
        return (ranges, String(rest))
    }
}

/// Works out how the tags wrap in the strip: the largest type size that fits the rows
/// allowed, and when none does, how many tags are left out ("+N more").
enum FitmentLayout {
    struct Plan {
        var lines: [[FitTag]] = []
        var fontSize: CGFloat = 11
        /// Tags that did not fit and are summed up as "+N more".
        var hidden: Int = 0
    }

    static let sizes: [CGFloat] = [11, 10, 9]
    static let tagGap: CGFloat = 4
    static let tagPadding: CGFloat = 5

    static func width(of tag: FitTag, size: CGFloat) -> CGFloat {
        let bold = UIFont.systemFont(ofSize: size, weight: .heavy)
        let light = UIFont.systemFont(ofSize: size, weight: .medium)
        var w = (tag.models as NSString).size(withAttributes: [.font: bold]).width
        if !tag.years.isEmpty {
            w += 4 + (tag.years as NSString).size(withAttributes: [.font: light]).width
        }
        return ceil(w) + 2 * tagPadding + 3
    }

    static func flow(_ tags: [FitTag], size: CGFloat, width: CGFloat) -> [[FitTag]] {
        var lines: [[FitTag]] = []
        var current: [FitTag] = []
        var used: CGFloat = 0
        for tag in tags {
            let w = self.width(of: tag, size: size)
            let needed = current.isEmpty ? w : used + tagGap + w
            if !current.isEmpty && needed > width {
                lines.append(current)
                current = [tag]
                used = w
            } else {
                current.append(tag)
                used = needed
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    static func plan(tags: [FitTag], width: CGFloat, maxRows: Int) -> Plan {
        if tags.isEmpty { return Plan() }
        for size in sizes {
            let lines = flow(tags, size: size, width: width)
            if lines.count <= maxRows {
                return Plan(lines: lines, fontSize: size, hidden: 0)
            }
        }
        let size = sizes.last ?? 9
        var kept: [FitTag] = Array(flow(tags, size: size, width: width).prefix(maxRows).joined())
        while true {
            let hidden = tags.count - kept.count
            let more = FitTag(models: "+\(hidden) more", years: "")
            let lines = flow(kept + [more], size: size, width: width)
            if lines.count <= maxRows || kept.isEmpty {
                return Plan(lines: lines, fontSize: size, hidden: hidden)
            }
            kept.removeLast()
        }
    }
}

/// Models already used on Library signs, for suggestions while typing.
func fitmentModelSuggestions(from signs: [Sign]) -> [FitmentModel] {
    var seen = Set<String>()
    var out: [FitmentModel] = []
    for sign in signs {
        for row in sign.fitmentRows ?? [] {
            for model in row.models {
                let key = model.name.trimmingCharacters(in: .whitespaces).lowercased()
                if key.isEmpty || seen.contains(key) { continue }
                seen.insert(key)
                out.append(FitmentModel(name: model.name, short: model.short))
            }
        }
    }
    return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
