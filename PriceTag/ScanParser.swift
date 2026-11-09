//
//  ScanParser.swift
//  PriceTag
//
//  Turns the text a camera read off a printed sign into a guess at the sign's fields.
//

import Foundation
import CoreGraphics

/// One piece of text the camera found, and where it sat in the picture.
nonisolated struct ScanItem: Hashable {
    var text: String
    /// Position in the picture as fractions of its size, origin at the top left.
    var box: CGRect
}

/// The fields a scan fills in.
enum ScanField: Hashable {
    case type, brand, name, variant, size, price, was, percent, partNumber, fitment, note
}

/// How sure the scan is about a field.
enum ScanMark {
    /// The text was found on the sign.
    case read
    /// The brand was recognised from its mark.
    case logo
    /// Not on the sign; worked out from the other prices.
    case worked
    /// A guess, or nothing found. Worth a look.
    case check

    var label: String {
        switch self {
        case .read:   return "Read"
        case .logo:   return "Logo found"
        case .worked: return "Worked out"
        case .check:  return "Check"
        }
    }
}

/// A line the scan read but could not place in any field.
struct ScanLeftover: Identifiable, Hashable {
    var id: Int
    var text: String
}

/// What a scan made of a sign: a guessed sign, how sure each field is, and the text itself.
struct ScanReading {
    var sign = Sign()
    var marks: [ScanField: ScanMark] = [:]
    /// Every line the camera read, top to bottom.
    var lines: [String] = []
    /// All the text as one string of upper-case letters and digits, for matching.
    var squashed: String = ""
    /// True when the brand was found; false when the sign's brand is only a stand-in.
    var brandFound = false
    /// Lines that did not fit any field. The review screen lets the user place them.
    var leftovers: [ScanLeftover] = []
    /// Brand logos that look like something in the photo, closest first. Filled in by the
    /// flow after reading, when the photo is there and the brand text was not.
    var logoCandidates: [LogoCandidate] = []
    /// How close each logo was, for checking the matching in test builds.
    var logoDebug = ""

    func mark(_ field: ScanField) -> ScanMark {
        return marks[field] ?? .check
    }

    /// The text as one line, for showing under the fields.
    var summaryText: String { return lines.joined(separator: " · ") }
}

/// Small text helpers shared by the parser and the matcher.
enum ScanText {
    /// Upper-case letters and digits only.
    static func squash(_ text: String) -> String {
        let kept = text.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(kept))
    }

    /// Upper-case words, split on anything that is not a letter or digit.
    static func words(_ text: String) -> [String] {
        return text.uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// How many single-character edits turn one string into the other.
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[y.count]
    }

    /// Digits only, so "$1043.95" and "104395" compare equal.
    static func digits(_ text: String) -> String {
        return text.filter { $0.isNumber }
    }

    /// Groups of a regular expression's first match; index 0 is the whole match.
    /// Groups that did not take part come back empty. Nil when nothing matches.
    static func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let found = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var groups: [String] = []
        for i in 0..<found.numberOfRanges {
            let range = found.range(at: i)
            groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return groups
    }
}

// MARK: - Prices

/// What word, if any, sat in front of an amount.
fileprivate enum MoneyLabel {
    case none, was, now, save
}

/// One dollar amount found on the sign.
fileprivate struct ScanMoney {
    var index: Int
    var value: Double
    var text: String
    var height: CGFloat
    var label: MoneyLabel
    var sure: Bool
}

/// Which amount is the price, which is the old price, and how sure that is.
fileprivate struct PricePick {
    var price: ScanMoney?
    var was: ScanMoney?
    var sure = true
    /// True when two amounts fit together as an old price and a new one.
    var paired = false
}

// MARK: - The parser

enum ScanParser {

    /// Guesses a sign from the lines of text a camera read.
    /// `brands` and `features` are the names the app has marks for.
    ///
    /// Nothing here depends on where things sit on the sheet, so signs made in other
    /// programs read the same way as the app's own: amounts are paired by the maths,
    /// fitment years are filled out, and anything unplaced is handed back as leftovers.
    static func read(_ items: [ScanItem], brands: [String], features: [String] = []) -> ScanReading {
        let list = items
            .map { ScanItem(text: tidy($0.text), box: $0.box) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.box.minY < $1.box.minY }

        var reading = ScanReading()
        reading.lines = list.map { $0.text }
        reading.squashed = ScanText.squash(reading.lines.joined(separator: " "))

        var texts = list.map { $0.text }
        var used = Set<Int>()
        var sign = Sign()
        var marks: [ScanField: ScanMark] = [:]
        let all = texts.map { $0.uppercased() }.joined(separator: " ")

        // MARK: Words that say what kind of sign this is

        let preOwned = all.contains("PRE-OWNED") || all.contains("PRE OWNED") || all.contains("PREOWNED")
        let endOfSeason = all.contains("END OF SEASON")
        let clearanceWord = all.contains("CLEARANCE")
        var saleWord = false
        var nowWord = false
        let labelWords: Set<String> = ["OFF", "FITS", "SAVE", "REG", "REGULAR", "ONLY", "PRICE", "WAS", "VIN"]
        for i in texts.indices {
            let up = texts[i].uppercased()
            let flat = ScanText.squash(up)
            if up.contains("PRE-OWNED") || up.contains("PRE OWNED") || up.contains("PREOWNED")
                || up.contains("END OF SEASON") || up.contains("CONFIRM FITMENT") || flat == "CLEARANCE" {
                used.insert(i)
            } else if flat == "SALE" {
                saleWord = true
                used.insert(i)
            } else if flat == "NOW" {
                nowWord = true
                used.insert(i)
            } else if labelWords.contains(flat) {
                used.insert(i)
            }
        }

        // MARK: % off

        var percent: String?
        for i in texts.indices where !used.contains(i) {
            guard let g = ScanText.match("(\\d{1,2})\\s*%", in: texts[i]) else { continue }
            percent = g[1]
            let rest = texts[i].replacingOccurrences(
                of: "(?i)(?:save\\s*)?\\d{1,2}\\s*%\\s*(?:off)?", with: " ", options: .regularExpression)
            let cleaned = tidy(rest)
            if ScanText.squash(cleaned).isEmpty {
                used.insert(i)
            } else {
                texts[i] = cleaned
            }
            break
        }

        // MARK: Fitment

        // A year range that wrapped onto the next line: "R 1250 GS (19-" then "20)".
        for i in texts.indices where !used.contains(i) {
            guard ScanText.match("\\(\\s*\\d{2,4}\\s*[-–—]?\\s*$", in: texts[i]) != nil else { continue }
            var best: Int?
            var bestGap = CGFloat.greatestFiniteMagnitude
            for j in texts.indices where j != i && !used.contains(j) {
                guard ScanText.match("^\\d{2,4}\\s*\\)", in: texts[j]) != nil else { continue }
                let gap = list[j].box.minY - list[i].box.minY
                if gap > -0.005 && gap < bestGap {
                    best = j
                    bestGap = gap
                }
            }
            if let j = best {
                texts[i] = texts[i] + texts[j]
                used.insert(j)
            }
        }

        var fitLines: [String] = []
        var yearOnly: [Int] = []
        for i in texts.indices where !used.contains(i) {
            var line = texts[i]
            let up = line.uppercased()
            if moneyIn(line) != nil || line.contains("$") { continue }
            let isFits = up.hasPrefix("FITS")
            if isFits {
                line = String(line.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
            }
            if up.contains("ALL MODELS") || up.contains("UNIVERSAL FIT") {
                sign.universalFit = true
                used.insert(i)
                continue
            }
            let expanded = expandYears(line)
            let hasYear = expanded != tidy(line)
                || ScanText.match("(?<![0-9.,$])(?:19|20)\\d{2}(?![0-9]|[.,][0-9])", in: expanded) != nil
            if !hasYear && !isFits { continue }
            used.insert(i)
            if expanded.isEmpty { continue }
            if hasYear && yearsOnly(expanded) {
                texts[i] = expanded
                yearOnly.append(i)
            } else {
                fitLines.append(expanded)
            }
        }
        // On the app's own signs the models print just left of their years.
        for i in yearOnly {
            var line = texts[i]
            let lefts = texts.indices.filter { !used.contains($0) && sitsLeftOf(list[$0].box, list[i].box) }
            if let left = lefts.max(by: { list[$0].box.maxX < list[$1].box.maxX }) {
                line = texts[left] + " " + line
                used.insert(left)
            }
            fitLines.append(line)
        }
        let hasFit = !fitLines.isEmpty || sign.universalFit == true
        if !fitLines.isEmpty {
            let rows = FitmentParser.rows(from: fitLines.joined(separator: "\n"))
            if !rows.isEmpty {
                sign.fitmentRows = rows
                sign.syncFitmentText()
            }
        }
        if hasFit { marks[.fitment] = .read }

        // MARK: Brand and feature marks

        var brandHit: (name: String, length: Int, item: Int?)?
        for name in brands {
            let full = ScanText.squash(name)
            if full.isEmpty { continue }
            var keys = [full]
            if let first = name.split(separator: " ").first, name.contains(" ") {
                let alias = ScanText.squash(String(first))
                if alias.count >= 3 { keys.append(alias) }
            }
            for key in keys {
                var hitItem: Int?
                var found = false
                for i in texts.indices where !used.contains(i) {
                    let flat = ScanText.squash(texts[i])
                    if flat.isEmpty { continue }
                    if flat == key || (flat.count <= key.count + 2 && flat.contains(key)) {
                        found = true
                        hitItem = i
                        break
                    }
                    if key.count >= 5 && flat.count >= 4 && ScanText.distance(flat, key) <= 1 {
                        found = true
                        hitItem = i
                        break
                    }
                }
                if !found && key.count >= 5 && reading.squashed.contains(key) { found = true }
                if found, brandHit == nil || key.count > brandHit!.length {
                    brandHit = (name, key.count, hitItem)
                }
            }
        }
        if let hit = brandHit {
            sign.brand = hit.name
            reading.brandFound = true
            marks[.brand] = .logo
            if let i = hit.item { used.insert(i) }
        } else {
            sign.brand = brands.first ?? ""
            marks[.brand] = .check
        }

        for name in features {
            let key = ScanText.squash(name)
            if key.count < 3 { continue }
            let hit = texts.indices.first { !used.contains($0) && ScanText.squash(texts[$0]) == key }
            if let i = hit {
                if !sign.featureLogos.contains(name) { sign.featureLogos.append(name) }
                used.insert(i)
            }
        }

        // MARK: Part number

        // One unbroken token with digits in it, printed smaller than the name.
        var tallest: CGFloat = 0
        for i in texts.indices where !used.contains(i) && moneyIn(texts[i]) == nil {
            tallest = max(tallest, list[i].box.height)
        }
        for i in texts.indices where !used.contains(i) {
            if tallest > 0 && list[i].box.height >= tallest * 0.85 { continue }
            var token = texts[i].trimmingCharacters(in: .whitespaces)
            if let g = ScanText.match("^(?:P/N|PN|PART\\s*(?:NO\\.?|NUMBER|#))[:#.\\s-]*(.+)$", in: token) {
                token = g[1].trimmingCharacters(in: .whitespaces)
            }
            let up = token.uppercased()
            guard up.count >= 5, up.count <= 26, !up.contains(" "), !up.contains("$"), !up.contains(","),
                  up.rangeOfCharacter(from: .decimalDigits) != nil,
                  ScanText.match("^[A-Z0-9][A-Z0-9\\-/.]*[A-Z0-9]$", in: up) != nil,
                  ScanText.match("^(?:19|20)\\d{2}", in: up) == nil,
                  ScanText.match("^\\d+\\.\\d{2}$", in: up) == nil else { continue }
            sign.partNumber = token
            marks[.partNumber] = .read
            used.insert(i)
            break
        }

        // A part number often gives the make away when no logo was found.
        if !reading.brandFound && !sign.partNumber.isEmpty {
            if let guess = brandFromPartNumber(sign.partNumber, brands: brands) {
                sign.brand = guess.name
                if let variant = guess.variant { sign.brandVariant = variant }
                reading.brandFound = true
                marks[.brand] = .worked
            }
        }

        // MARK: Amounts

        var monies: [ScanMoney] = []
        for i in texts.indices where !used.contains(i) {
            guard let found = moneyIn(texts[i]) else { continue }
            if found.label == .save {
                used.insert(i)
                continue
            }
            var text = found.text
            var sure = found.sure
            if !text.contains("."), let j = centsNeighbour(of: i, in: list, texts: texts, used: used) {
                // Two digits are the cents. One digit is a superscript that lost its partner.
                let cents = texts[j].trimmingCharacters(in: .whitespaces)
                text += "." + cents
                used.insert(j)
                sure = cents.count == 2
            }
            let value = Double(text) ?? 0
            if value <= 0 { continue }
            monies.append(ScanMoney(index: i, value: value, text: text, height: list[i].box.height,
                                    label: found.label, sure: sure))
        }
        let picked = pickPrices(monies, percent: percent.flatMap { Double($0) })
        var price: String?
        var was: String?
        var priceMark = ScanMark.read
        var wasMark = ScanMark.read
        if let m = picked.price {
            price = m.text
            used.insert(m.index)
            priceMark = (m.sure && picked.sure) ? .read : .check
        }
        if let m = picked.was {
            was = m.text
            used.insert(m.index)
            wasMark = (m.sure && picked.sure) ? .read : .check
        }

        // MARK: Colour, size and condition

        // They often share a line, with the size in brackets: "BLACK (XL)".
        for i in texts.indices where !used.contains(i) {
            guard let g = ScanText.match("^(.*?)\\(([^)]{1,8})\\)(.*)$", in: texts[i]) else { continue }
            let inside = g[2].trimmingCharacters(in: .whitespaces)
            if ScanText.match("^\\d{2,4}\\s*[-–—]", in: inside) != nil { continue }
            var colour = g[1].trimmingCharacters(in: .whitespaces)
            let after = g[3].trimmingCharacters(in: .whitespaces)
            sign.size = inside
            marks[.size] = .read
            // The first half of a colour that wrapped onto the line above: "SOLID MATTE".
            if let above = lineAbove(i, in: list, texts: texts, used: used), colourShare(texts[above]) >= 0.5 {
                colour = colour.isEmpty ? texts[above] : texts[above] + " " + colour
                used.insert(above)
            }
            if !colour.isEmpty {
                sign.variant = sentence(colour)
                marks[.variant] = .read
            }
            if !after.isEmpty { sign.condition = after.capitalized }
            used.insert(i)
            break
        }

        // MARK: Name

        // The biggest text left, joined with a second line right under it.
        var eligible: [Int] = []
        for i in texts.indices where !used.contains(i) {
            let flat = ScanText.squash(texts[i])
            if flat.count < 2 || Int(flat) != nil || moneyIn(texts[i]) != nil { continue }
            if colourShare(texts[i]) >= 0.99 { continue }
            eligible.append(i)
        }
        if let first = eligible.max(by: { list[$0].box.height < list[$1].box.height }) {
            var name = texts[first]
            used.insert(first)
            let second = eligible.first { j in
                j != first && continuesName(list[j].box, below: list[first].box)
            }
            if let j = second {
                name += " " + texts[j]
                used.insert(j)
            }
            sign.name = name
            marks[.name] = .read
        } else {
            marks[.name] = .check
        }

        // Colour or size on lines of their own.
        if sign.variant.isEmpty {
            let parts = texts.indices.filter { !used.contains($0) && colourShare(texts[$0]) >= 0.99 }
            if !parts.isEmpty {
                let chosen = Array(parts.prefix(3))
                sign.variant = sentence(chosen.map { texts[$0] }.joined(separator: " "))
                marks[.variant] = .read
                for i in chosen { used.insert(i) }
            }
        }
        if sign.size.isEmpty {
            for i in texts.indices where !used.contains(i) {
                let t = texts[i].trimmingCharacters(in: .whitespaces).uppercased()
                var size: String?
                if let g = ScanText.match("^SIZE[:\\s]*([A-Z0-9.]{1,4})$", in: t) {
                    size = g[1]
                } else if ScanText.match("^(?:XXS|XS|S|M|L|XL|XXL|XXXL|2XL|3XL|4XL)$", in: t) != nil {
                    size = t
                }
                if let s = size {
                    sign.size = s
                    marks[.size] = .read
                    used.insert(i)
                    break
                }
            }
        }

        // MARK: Left over

        // Only lines that say "note"-like things go in the note; the rest wait to be placed.
        var noteParts: [String] = []
        var leftovers: [ScanLeftover] = []
        for i in texts.indices where !used.contains(i) {
            if ScanText.squash(texts[i]).count < 2 { continue }
            if isNote(texts[i]) {
                noteParts.append(texts[i])
            } else {
                leftovers.append(ScanLeftover(id: i, text: texts[i]))
            }
        }
        if !noteParts.isEmpty {
            sign.note = noteParts.joined(separator: " ")
            marks[.note] = .check
        }
        reading.leftovers = leftovers

        // MARK: What kind of sign it is

        if preOwned || hasFit {
            sign.type = .used
            sign.markPreOwned = preOwned
            marks[.type] = .read
        } else if endOfSeason || clearanceWord {
            sign.type = .clearance
            marks[.type] = .read
        } else if saleWord || nowWord || percent != nil {
            sign.type = .sale
            marks[.type] = .read
        } else if picked.paired {
            sign.type = .sale
            marks[.type] = .check
        } else if !sign.partNumber.isEmpty {
            sign.type = .used
            sign.markPreOwned = false
            marks[.type] = .check
        } else {
            sign.type = .regular
            // No banner and no second price: it could be a regular item or apparel.
            marks[.type] = .check
        }

        // MARK: Prices, with whichever of the three is missing worked out from the other two

        sign.price = price ?? ""
        marks[.price] = price == nil ? .check : priceMark
        if sign.usesComparison {
            sign.regularPrice = was ?? ""
            sign.percentOff = percent ?? ""
            if was != nil { marks[.was] = wasMark }
            if percent != nil { marks[.percent] = .read }
            if sign.price.isEmpty, let v = PriceSuggestion.derivePrice(was: sign.regularPrice, percent: sign.percentOff) {
                sign.price = v
                marks[.price] = .worked
            }
            if sign.percentOff.isEmpty, let v = PriceSuggestion.derivePercent(was: sign.regularPrice, price: sign.price) {
                sign.percentOff = v
                marks[.percent] = .worked
            }
            if sign.regularPrice.isEmpty, let v = PriceSuggestion.deriveWas(price: sign.price, percent: sign.percentOff) {
                sign.regularPrice = v
                marks[.was] = .worked
            }
            // A price whose cents were cut off or doubtful: the old price and percent can finish it.
            if marks[.price] == .check, let read = Double(sign.price),
               let v = PriceSuggestion.derivePrice(was: sign.regularPrice, percent: sign.percentOff),
               let worked = Double(v), abs(worked - read) < 1.0 {
                sign.price = v
                marks[.price] = .worked
            }
        }

        reading.sign = sign
        reading.marks = marks
        return reading
    }

    // MARK: Picking the prices

    /// Decides which amount is the price and which is the old price.
    ///
    /// The price on a sale sign is always lower than the old price, so the numbers settle
    /// it. Where two amounts fit the percent off, they win over any word or print size.
    fileprivate static func pickPrices(_ all: [ScanMoney], percent: Double?) -> PricePick {
        var pool = all
        var out = PricePick()

        // Amounts printed with their own WAS or NOW.
        if let i = pool.firstIndex(where: { $0.label == .was }) { out.was = pool.remove(at: i) }
        if let i = pool.firstIndex(where: { $0.label == .now }) { out.price = pool.remove(at: i) }
        if let w = out.was, let p = out.price, p.value >= w.value {
            // The labels disagree with the maths. Trust the numbers.
            pool.append(w)
            pool.append(p)
            out.was = nil
            out.price = nil
        }
        if out.was != nil && out.price != nil {
            out.paired = true
            return out
        }
        if let w = out.was {
            out.price = tallest(pool.filter { $0.value < w.value })
            out.paired = out.price != nil
            return out
        }
        if let p = out.price {
            let higher = pool.filter { $0.value > p.value }
            if let pct = percent, let fit = higher.first(where: { fits(old: $0.value, new: p.value, percent: pct) }) {
                out.was = fit
            } else {
                out.was = tallest(higher)
            }
            out.paired = out.was != nil
            return out
        }

        // No words to go on.
        if pool.count >= 2 {
            if let pct = percent, let pair = bestPair(pool, percent: pct) {
                out.was = pair.hi
                out.price = pair.lo
                out.paired = true
                return out
            }
            let bySize = pool.sorted { $0.height > $1.height }
            let a = bySize[0]
            let b = bySize[1]
            if a.value == b.value {
                out.price = a
                return out
            }
            let hi = a.value > b.value ? a : b
            let lo = a.value > b.value ? b : a
            let ratio = lo.value / hi.value
            if ratio < 0.25 || ratio > 0.99 {
                // Too far apart (or too close) to be an old price and a new one.
                out.price = a
                out.sure = false
                return out
            }
            out.was = hi
            out.price = lo
            out.paired = true
            // The sale price is normally the bigger print.
            out.sure = lo.index == a.index
            return out
        }
        out.price = pool.first
        return out
    }

    fileprivate static func tallest(_ list: [ScanMoney]) -> ScanMoney? {
        return list.max(by: { $0.height < $1.height })
    }

    /// True when `new` is `old` less `percent`, give or take a rounding.
    fileprivate static func fits(old: Double, new: Double, percent: Double) -> Bool {
        let expected = old * (1 - percent / 100)
        let allowed = max(1.0, old * 0.02)
        return abs(expected - new) <= allowed
    }

    /// The two amounts that best fit the percent off, as (old, new).
    fileprivate static func bestPair(_ pool: [ScanMoney], percent: Double) -> (hi: ScanMoney, lo: ScanMoney)? {
        var best: (hi: ScanMoney, lo: ScanMoney, error: Double)?
        for hi in pool {
            for lo in pool where lo.value < hi.value {
                guard fits(old: hi.value, new: lo.value, percent: percent) else { continue }
                let error = abs(hi.value * (1 - percent / 100) - lo.value)
                if best == nil || error < best!.error {
                    best = (hi, lo, error)
                }
            }
        }
        if let b = best { return (b.hi, b.lo) }
        return nil
    }

    // MARK: Helpers

    /// The small cents printed beside and a little above a whole-dollar amount.
    private static func centsNeighbour(of i: Int, in list: [ScanItem], texts: [String], used: Set<Int>) -> Int? {
        let main = list[i].box
        for j in texts.indices where j != i && !used.contains(j) {
            let flat = texts[j].trimmingCharacters(in: .whitespaces)
            guard flat.count <= 2, Int(flat) != nil else { continue }
            let other = list[j].box
            let toRight = other.minX >= main.maxX - 0.03
            let near = other.minX - main.maxX < 0.12
            let level = abs(other.midY - main.midY) < main.height
            let smaller = other.height < main.height
            // A lone digit has to sit up in the corner, the way a superscript does.
            let raised = flat.count == 2 || other.midY < main.midY
            if toRight && near && level && smaller && raised { return j }
        }
        return nil
    }

    /// The closest line right above `i` and about the same size.
    private static func lineAbove(_ i: Int, in list: [ScanItem], texts: [String], used: Set<Int>) -> Int? {
        let base = list[i].box
        var best: Int?
        var bestGap = CGFloat.greatestFiniteMagnitude
        for j in texts.indices where j != i && !used.contains(j) {
            let box = list[j].box
            let gap = base.minY - box.maxY
            let sameSize = box.height > base.height * 0.6 && box.height < base.height * 1.6
            let overlaps = box.minX < base.maxX && box.maxX > base.minX
            if gap > -0.01 && gap < base.height * 1.2 && sameSize && overlaps && gap < bestGap {
                best = j
                bestGap = gap
            }
        }
        return best
    }

    /// True when `a` is on the same line as `b` and just to its left.
    private static func sitsLeftOf(_ a: CGRect, _ b: CGRect) -> Bool {
        let sameRow = abs(a.midY - b.midY) < 0.03
        let gap = b.minX - a.maxX
        return sameRow && gap > -0.01 && gap < 0.06
    }

    /// True when `a` looks like the second line of a name printed in `b`: right under it,
    /// about as tall, and overlapping it sideways.
    private static func continuesName(_ a: CGRect, below b: CGRect) -> Bool {
        let drop = a.minY - b.maxY
        let closeEnough = drop > -0.01 && drop < b.height * 0.8
        let similarSize = a.height >= b.height * 0.75
        let overlaps = a.minX < b.maxX && a.maxX > b.minX
        return closeEnough && similarSize && overlaps
    }

    /// Collapses runs of spaces and trims the ends.
    private static func tidy(_ text: String) -> String {
        let parts = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// First letter up, the rest down: "SOLID MATTE BLACK" as "Solid matte black".
    private static func sentence(_ text: String) -> String {
        let lower = text.lowercased()
        guard let first = lower.first else { return lower }
        return first.uppercased() + lower.dropFirst()
    }

    private static let colourWords: Set<String> = [
        "BLACK", "WHITE", "RED", "BLUE", "GREEN", "YELLOW", "ORANGE", "GREY", "GRAY", "SILVER", "MATTE", "MATT",
        "GLOSS", "GLOSSY", "FLAT", "SOLID", "METALLIC", "PEARL", "CARBON", "CAMO", "HI", "VIZ", "HIVIZ", "NEON",
        "BROWN", "TAN", "PINK", "PURPLE", "TITANIUM", "CHROME", "GOLD", "BRONZE", "TEAL", "CREAM", "CHARCOAL",
        "OLIVE", "NAVY", "LIME", "BURGUNDY", "GRAPHITE", "ANTHRACITE", "SAND", "COPPER", "SEMI", "DARK", "LIGHT"
    ]

    /// How much of a line is colour words (0 to 1). Lines with digits are never colours.
    private static func colourShare(_ text: String) -> Double {
        if text.contains(where: { $0.isNumber }) { return 0 }
        let words = ScanText.words(text)
        if words.isEmpty { return 0 }
        let hits = words.filter { colourWords.contains($0) }.count
        return Double(hits) / Double(words.count)
    }

    /// True for lines that read like a note on the sign.
    private static func isNote(_ text: String) -> Bool {
        let keys = ["NOTE", "NOTES", "FINAL SALE", "NO RETURN", "NO RETURNS", "NO REFUND", "SPECIAL ORDER",
                    "WHILE SUPPLIES", "OPEN BOX", "AS IS", "DISPLAY MODEL", "SEE STORE"]
        let padded = " " + ScanText.words(text).joined(separator: " ") + " "
        return keys.contains { padded.contains(" " + $0 + " ") }
    }

    /// The make a part number points to, when the numbering is distinctive.
    private static func brandFromPartNumber(_ part: String, brands: [String]) -> (name: String, variant: String?)? {
        let token = part.trimmingCharacters(in: .whitespaces).uppercased()
        func brand(containing word: String) -> String? {
            return brands.first { $0.lowercased().contains(word) }
        }
        if ScanText.match("^\\d{11}$", in: token) != nil, let name = brand(containing: "bmw") {
            return (name, "Parts")
        }
        if ScanText.match("^\\d{5}-\\d{4}$", in: token) != nil, let name = brand(containing: "kawasaki") {
            return (name, "Parts")
        }
        if ScanText.match("^A\\d{7}$", in: token) != nil, let name = brand(containing: "triumph") {
            return (name, nil)
        }
        return nil
    }

    // MARK: Years

    /// Two-digit years: 60 and up are 19xx, the rest 20xx.
    private static func fullYear(_ text: String) -> Int {
        let value = Int(text) ?? 0
        if text.count == 4 { return value }
        return value >= 60 ? 1900 + value : 2000 + value
    }

    /// Writes bracketed years out in full: "R 1250 GS (19-20)" as "R 1250 GS 2019-2020".
    private static func expandYears(_ line: String) -> String {
        let pattern = "\\(\\s*((?:19|20)\\d{2}|\\d{2})\\s*[-–—]\\s*((?:19|20)\\d{2}|\\d{2})\\s*\\)"
            + "|\\(\\s*((?:19|20)\\d{2})\\s*\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return tidy(line) }
        let ns = line as NSString
        let found = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        let out = NSMutableString(string: line)
        for m in found.reversed() {
            var text = " "
            if m.range(at: 3).location != NSNotFound {
                text = " " + ns.substring(with: m.range(at: 3)) + " "
            } else {
                let a = fullYear(ns.substring(with: m.range(at: 1)))
                let b = fullYear(ns.substring(with: m.range(at: 2)))
                text = " \(a)-\(b) "
            }
            out.replaceCharacters(in: m.range, with: text)
        }
        return tidy(String(out))
    }

    /// True when a line is nothing but a year or a range of years.
    private static func yearsOnly(_ line: String) -> Bool {
        return ScanText.match("^(?:19|20)\\d{2}(?:\\s*[-–—]\\s*(?:19|20)\\d{2})?$", in: line) != nil
    }

    // MARK: Amounts in text

    fileprivate struct MoneyRead {
        var label: MoneyLabel
        var text: String
        var sure: Bool
    }

    /// An amount that fills a whole line, such as "$1,043.95", "WAS $1309.95" or "$588 60".
    /// Bare digits without a dollar sign, cents or a word in front are not amounts.
    fileprivate static func moneyIn(_ text: String) -> MoneyRead? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = "^(WAS|NOW|REGULAR|REG|SALE|SAVE|ONLY)?[\\s:\\-]*\\$?\\s*([0-9][0-9,]*)(?:\\.([0-9]{0,2}))?(?:\\s+([0-9]{2}))?$"
        guard let g = ScanText.match(pattern, in: trimmed) else { return nil }
        let word = g[1].uppercased()
        let dotCents = g[3]
        let spaceCents = g[4]
        if !dotCents.isEmpty && !spaceCents.isEmpty { return nil }
        if !trimmed.contains("$") && dotCents.isEmpty && word.isEmpty { return nil }

        var dollars = g[2].replacingOccurrences(of: ",", with: "")
        var cents = dotCents.isEmpty ? spaceCents : dotCents
        var sure = cents.count != 1
        if cents.isEmpty {
            if dollars.count >= 5 && !g[2].contains(",") {
                // The small cents were read as part of the dollars.
                cents = String(dollars.suffix(2))
                dollars = String(dollars.dropLast(2))
                sure = false
            } else if dollars.count >= 4 {
                sure = false
            }
        }
        var label = MoneyLabel.none
        if word == "WAS" || word == "REG" || word == "REGULAR" { label = .was }
        if word == "NOW" || word == "SALE" { label = .now }
        if word == "SAVE" { label = .save }
        let value = cents.isEmpty ? dollars : dollars + "." + cents
        return MoneyRead(label: label, text: value, sure: sure)
    }
}
