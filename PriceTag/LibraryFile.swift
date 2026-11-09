//
//  LibraryFile.swift
//  PriceTag
//
//  One file that carries a Library from one phone to another.
//

import SwiftUI
import Foundation

/// What goes into the file. It is plain JSON, so it can be opened and checked by hand.
struct LibraryFile: Codable {
    static let formatName = "pricetag-library"
    static let currentVersion = 1

    /// A logo whose artwork was added or replaced on the phone that made the file.
    /// Artwork that ships inside the app is left out; every phone already has it.
    struct LogoEntry: Codable {
        var name: String
        var kind: LogoKind
        var variant: String?
        /// The PNG, which JSON stores as text.
        var png: Data
    }

    var format: String = LibraryFile.formatName
    var version: Int = LibraryFile.currentVersion
    var exportedAt: Date = Date()
    var exportedBy: String
    var signs: [Sign]
    var pages: [SignPage]
    var favourites: [UUID]
    var logos: [LogoEntry]
}

enum LibraryImportError: LocalizedError {
    case notALibraryFile
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .notALibraryFile:
            return "That isn't a PriceTag Library file."
        case .newerVersion:
            return "That file was made by a newer version of PriceTag. Update the app and try again."
        }
    }
}

/// What an import did, so nothing changes without the person being told.
struct LibraryImportSummary {
    var added = 0
    var updated = 0
    var unchanged = 0
    var pagesAdded = 0
    var pagesSkipped = 0
    var logosAdded = 0
    var starsAdded = 0
    var cameInAsPersonalCopies = false

    var text: String {
        var lines: [String] = []

        var signParts: [String] = []
        if added > 0 { signParts.append("\(added) added") }
        if updated > 0 { signParts.append("\(updated) updated to the newer version") }
        if unchanged > 0 { signParts.append("\(unchanged) already up to date") }
        if signParts.isEmpty {
            lines.append("There were no signs in the file.")
        } else {
            lines.append("Signs: " + signParts.joined(separator: ", ") + ".")
        }

        var pageParts: [String] = []
        if pagesAdded > 0 { pageParts.append("\(pagesAdded) added") }
        if pagesSkipped > 0 { pageParts.append("\(pagesSkipped) already here") }
        if !pageParts.isEmpty {
            lines.append("Pages: " + pageParts.joined(separator: ", ") + ".")
        }

        if logosAdded > 0 { lines.append("Logos added: \(logosAdded).") }
        if starsAdded > 0 { lines.append("Favourites added: \(starsAdded).") }
        if cameInAsPersonalCopies {
            lines.append("The new signs came in as your personal copies.")
        }
        return lines.joined(separator: "\n")
    }
}

extension Store {

    /// What this account puts in a Library file. Admins send the shared Library and the
    /// logos they added. Everyone sends their own personal copies, favourites and Pages.
    func makeLibraryFile() -> LibraryFile {
        let signs: [Sign]
        if account.isAdmin {
            signs = visibleLibrary
        } else {
            signs = library.filter { $0.isPersonal == true && $0.createdBy == account.id }
        }
        let ids = Set(signs.map { $0.id })
        return LibraryFile(
            exportedBy: account.name,
            signs: signs,
            pages: pages,
            favourites: Array(favouriteIDs.filter { ids.contains($0) }),
            logos: account.isAdmin ? LogoLibrary.shared.exportableLogos() : []
        )
    }

    /// Writes the file somewhere temporary and returns where, ready for the share sheet.
    func writeLibraryFile() throws -> URL {
        let data = try JSONEncoder().encode(makeLibraryFile())
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PriceTag Library " + day.string(from: Date()) + ".json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Adds what is missing and keeps whichever copy of a sign is newer.
    ///
    /// Importing never removes anything and never replaces a sign with an older one.
    /// Only an admin brings in shared signs; for anyone else every sign arrives as a
    /// personal copy, the same as a change they could not make directly.
    func importLibrary(from data: Data) throws -> LibraryImportSummary {
        let file: LibraryFile
        do {
            file = try JSONDecoder().decode(LibraryFile.self, from: data)
        } catch {
            throw LibraryImportError.notALibraryFile
        }
        guard file.format == LibraryFile.formatName else { throw LibraryImportError.notALibraryFile }
        guard file.version <= LibraryFile.currentVersion else { throw LibraryImportError.newerVersion }

        var summary = LibraryImportSummary()
        // Each sign's ID in the file, and the ID it ended up with here.
        var idHere: [UUID: UUID] = [:]
        var next = library

        for incoming in file.signs {
            var sign = incoming
            sign.libraryID = nil
            sign.isFavourite = nil

            let personal = !account.isAdmin || incoming.isPersonal == true
            if personal {
                sign.isPersonal = true
                sign.createdBy = account.id
            } else {
                sign.isPersonal = nil
                sign.basedOn = nil
            }

            if let j = next.firstIndex(where: { $0.id == sign.id }) {
                let existing = next[j]
                // A personal copy belongs to its maker; a shared sign to the admin.
                let mine = existing.isPersonal == true
                    ? existing.createdBy == account.id
                    : account.isAdmin
                if mine {
                    if (sign.savedAt ?? Date.distantPast) > (existing.savedAt ?? Date.distantPast) {
                        sign.createdBy = existing.createdBy
                        sign.isPersonal = existing.isPersonal
                        sign.basedOn = existing.basedOn
                        next[j] = sign
                        summary.updated += 1
                    } else {
                        summary.unchanged += 1
                    }
                    idHere[incoming.id] = existing.id
                    continue
                }
                // Someone else's entry already has this ID, so this arrives as a
                // separate personal copy.
                sign.id = UUID()
                sign.isPersonal = true
                sign.createdBy = account.id
                sign.basedOn = existing.isPersonal == true ? nil : existing.id
            }

            if sign.isPersonal == true, let base = sign.basedOn,
               !next.contains(where: { $0.id == base }) {
                sign.basedOn = nil
            }
            next.append(sign)
            summary.added += 1
            idHere[incoming.id] = sign.id
        }
        library = next

        var stars = favouriteIDs
        for old in file.favourites {
            if let id = idHere[old], stars.insert(id).inserted {
                summary.starsAdded += 1
            }
        }
        favouriteIDs = stars

        var nextPages = pages
        for page in file.pages {
            if nextPages.contains(where: { $0.id == page.id }) {
                summary.pagesSkipped += 1
            } else {
                nextPages.append(page)
                summary.pagesAdded += 1
            }
        }
        pages = nextPages

        if account.isAdmin {
            let logos = LogoLibrary.shared
            for entry in file.logos {
                let variant = entry.variant ?? ""
                let existing = logos.versions(of: entry.name, kind: entry.kind).first {
                    $0.variantLabel.caseInsensitiveCompare(variant) == .orderedSame
                }
                // Artwork already on this phone is never replaced.
                if let existing = existing, logos.hasArtwork(id: existing.id) { continue }
                guard let asset = logos.add(name: entry.name, kind: entry.kind, variant: variant) else { continue }
                if logos.setImage(data: entry.png, for: asset.id) {
                    summary.logosAdded += 1
                }
            }
        }

        summary.cameInAsPersonalCopies = !account.isAdmin && summary.added > 0
        return summary
    }
}
