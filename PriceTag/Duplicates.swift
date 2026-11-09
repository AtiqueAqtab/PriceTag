//
//  Duplicates.swift
//  PriceTag
//
//  Warns before the Library gets a second copy of a sign it already has.
//

import Foundation

extension Store {

    /// Library entries this account can see that look like `sign`: the same part number
    /// (capitals, spaces and dashes ignored, three characters or more), or the same brand,
    /// name, colour and size. The entry `sign` came from is never counted. Personal copies
    /// of other people are not in `visibleLibrary`, so they are never compared.
    func duplicates(of sign: Sign) -> [Sign] {
        let part = ScanText.squash(sign.partNumber)
        let name = ScanText.squash(sign.name)
        let brand = ScanText.squash(sign.brand)
        let colour = ScanText.squash(sign.variant)
        let size = ScanText.squash(sign.size)

        return visibleLibrary.filter { entry in
            if entry.id == sign.libraryID || entry.id == sign.id { return false }
            if part.count >= 3 && ScanText.squash(entry.partNumber) == part { return true }
            return !name.isEmpty
                && ScanText.squash(entry.name) == name
                && ScanText.squash(entry.brand) == brand
                && ScanText.squash(entry.variant) == colour
                && ScanText.squash(entry.size) == size
        }
    }

    /// True when saving `sign` would add a new Library entry, not update one.
    func wouldAddNewEntry(_ sign: Sign) -> Bool {
        guard let linked = sign.libraryID else { return true }
        return !visibleLibrary.contains { $0.id == linked }
    }

    /// The first look-alike, if saving `sign` would add a new entry.
    func lookAlike(for sign: Sign) -> (match: Sign, others: Int)? {
        guard wouldAddNewEntry(sign) else { return nil }
        let found = duplicates(of: sign)
        guard let first = found.first else { return nil }
        return (first, found.count - 1)
    }
}

extension Sign {
    /// "Shoei RF-1400 · Matte black · M", for the duplicate warning.
    var duplicateSummary: String {
        let parts = [brand, name, variant, size, partNumber]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

/// The wording of the warning.
enum DuplicateWarning {
    static let title = "Already in the Library?"

    static func message(_ found: (match: Sign, others: Int)) -> String {
        var text = "\u{201C}" + found.match.duplicateSummary + "\u{201D} looks like this sign."
        if found.others > 0 {
            text += " (And \(found.others) more like it.)"
        }
        text += " Open it to change it instead, or save this one as a separate sign."
        return text
    }
}
