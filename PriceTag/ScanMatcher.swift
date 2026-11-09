//
//  ScanMatcher.swift
//  PriceTag
//
//  Ranks Library signs against what a scan read.
//

import Foundation

/// One reason a Library sign looks like (or unlike) the scanned one.
struct ScanReason: Hashable {
    var text: String
    var matched: Bool
}

/// How close a Library sign is to the scan.
enum ScanStrength: Int, Comparable {
    case weak, possible, strong

    static func < (a: ScanStrength, b: ScanStrength) -> Bool { return a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .strong:   return "Strong match"
        case .possible: return "Possible"
        case .weak:     return "Weak"
        }
    }
}

struct ScanMatch: Identifiable {
    var sign: Sign
    var score: Int
    var strength: ScanStrength
    var reasons: [ScanReason]

    var id: UUID { return sign.id }
}

enum ScanMatcher {

    /// Library signs that look like the scan, best first. Weak matches are kept so the
    /// "No close match" screen can offer them; anything weaker is dropped.
    /// Pass only signs the current account can see.
    static func rank(_ reading: ScanReading, in library: [Sign], limit: Int = 6) -> [ScanMatch] {
        var matches: [ScanMatch] = []
        for candidate in library {
            if let match = score(candidate, against: reading) { matches.append(match) }
        }
        matches.sort { $0.score > $1.score }
        return Array(matches.prefix(limit))
    }

    private static func score(_ sign: Sign, against reading: ScanReading) -> ScanMatch? {
        let scanned = reading.sign
        let text = reading.squashed
        let words = ScanText.words(reading.lines.joined(separator: " "))
        var total = 0
        var reasons: [ScanReason] = []
        var partMatched = false

        // Part number: the strongest clue there is.
        let part = ScanText.squash(sign.partNumber)
        if part.count >= 4 {
            if text.contains(part) {
                total += 60
                partMatched = true
                reasons.append(ScanReason(text: "Part number", matched: true))
            } else if !scanned.partNumber.isEmpty {
                reasons.append(ScanReason(text: "Part number differs", matched: false))
            }
        }

        // Brand.
        let brandKey = ScanText.squash(sign.brand)
        if reading.brandFound {
            if ScanText.squash(scanned.brand) == brandKey {
                total += 15
                reasons.append(ScanReason(text: "Brand", matched: true))
            } else {
                total -= 10
                reasons.append(ScanReason(text: "Brand differs", matched: false))
            }
        } else if brandKey.count >= 4 && text.contains(brandKey) {
            total += 15
            reasons.append(ScanReason(text: "Brand", matched: true))
        }

        // Name: how many of its words are on the scan.
        let nameWords = ScanText.words(sign.name).filter { $0.count >= 2 }
        if !nameWords.isEmpty {
            let found = nameWords.filter { present($0, in: words, squashed: text) }.count
            var fraction = Double(found) / Double(nameWords.count)
            // The other way round too: a scan that says "GT-AIR 3 LILT" is closer to the
            // Lilt than to a plain GT-Air 3, even though every word of the plain name is in it.
            let readWords = ScanText.words(scanned.name).filter { $0.count >= 2 }
            if !readWords.isEmpty {
                let back = readWords.filter { nameWords.contains($0) }.count
                fraction = (fraction + Double(back) / Double(readWords.count)) / 2
            }
            total += Int((40.0 * fraction).rounded())
            if fraction >= 0.75 {
                reasons.append(ScanReason(text: "Name", matched: true))
            } else if fraction > 0 {
                reasons.append(ScanReason(text: "Name partly", matched: false))
            } else {
                reasons.append(ScanReason(text: "Name", matched: false))
            }
        }

        // Size and colour.
        let size = ScanText.squash(sign.size)
        if !size.isEmpty && !scanned.size.isEmpty {
            if size == ScanText.squash(scanned.size) {
                total += 5
                reasons.append(ScanReason(text: "Size", matched: true))
            } else {
                reasons.append(ScanReason(text: "Size differs", matched: false))
            }
        }
        let colourWords = ScanText.words(sign.variant).filter { $0.count >= 3 }
        if !colourWords.isEmpty {
            let found = colourWords.filter { present($0, in: words, squashed: text) }.count
            if Double(found) / Double(colourWords.count) >= 0.75 {
                total += 5
                reasons.append(ScanReason(text: "Colour", matched: true))
            } else if !scanned.variant.isEmpty {
                reasons.append(ScanReason(text: "Colour differs", matched: false))
            }
        }

        // Price. A different price is not a reason to rule a sign out: the whole point of
        // scanning is often to change it.
        if !sign.price.isEmpty && !scanned.price.isEmpty {
            if ScanText.digits(sign.price) == ScanText.digits(scanned.price) {
                total += 10
                reasons.append(ScanReason(text: "Price", matched: true))
            } else {
                reasons.append(ScanReason(text: "Price differs", matched: false))
            }
        }

        // Kind of sign.
        if sign.type == scanned.type && reading.mark(.type) == .read {
            total += 4
            reasons.append(ScanReason(text: "Type", matched: true))
        }

        // Fitment: the models on the sign against the text.
        let models = ScanText.words(sign.fitTags.map { $0.models }.joined(separator: " ")).filter { $0.count >= 2 }
        if !models.isEmpty {
            let found = models.filter { present($0, in: words, squashed: text) }.count
            if Double(found) / Double(models.count) >= 0.5 {
                total += 5
                reasons.append(ScanReason(text: "Fitment", matched: true))
            }
        }

        let points = max(total, 0)
        let strength: ScanStrength
        if partMatched || points >= 70 {
            strength = .strong
        } else if points >= 45 {
            strength = .possible
        } else if points >= 25 {
            strength = .weak
        } else {
            return nil
        }

        // Matched reasons first, so the strongest evidence reads first.
        let ordered = reasons.filter { $0.matched } + reasons.filter { !$0.matched }
        return ScanMatch(sign: sign, score: points, strength: strength, reasons: ordered)
    }

    /// Whether a word from a Library sign shows up in the scanned text, allowing for one
    /// misread letter in longer words.
    private static func present(_ word: String, in words: [String], squashed: String) -> Bool {
        if words.contains(word) { return true }
        if word.count >= 5 {
            if squashed.contains(word) { return true }
            return words.contains { ScanText.distance($0, word) <= 1 }
        }
        return false
    }

    // MARK: What changed

    /// The ways the printed sign differs from the Library entry, in words.
    static func differences(_ reading: ScanReading, from sign: Sign) -> [String] {
        let scanned = reading.sign
        var out: [String] = []
        func compare(_ label: String, _ now: String, _ saved: String, money: Bool) {
            if now.isEmpty || saved.isEmpty { return }
            let same = money
                ? ScanText.digits(now) == ScanText.digits(saved)
                : ScanText.squash(now) == ScanText.squash(saved)
            if same { return }
            let shownNow = money ? "$" + now : now
            let shownSaved = money ? "$" + saved : saved
            out.append(label + ": sign says " + shownNow + ", Library has " + shownSaved)
        }
        compare("Price", scanned.price, sign.price, money: true)
        if scanned.usesComparison && sign.usesComparison {
            compare("Was price", scanned.regularPrice, sign.regularPrice, money: true)
            compare("% off", scanned.percentOff, sign.percentOff, money: false)
        }
        if reading.mark(.type) == .read && scanned.type != sign.type {
            out.append("Type: sign looks like " + scanned.type.title + ", Library has " + sign.type.title)
        }
        return out
    }
}
