//
//  Models.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-13.
//

import Foundation

/// The kinds of sign the app can make.
///
/// The type decides which fields the editor shows and which ones
/// get drawn on the sign. Old saved data with retired type names
/// is mapped to a current type when it loads.
enum SignType: String, Codable, CaseIterable, Identifiable {
    case regular
    case sale
    case clearance
    case used
    case apparel

    var id: String { return rawValue }

    /// Signs saved before the parts and pre-owned types were merged decode as .used,
    /// which now covers both.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SignType(rawValue: raw) ?? (raw == "parts" ? .used : .regular)
    }

    var title: String {
        switch self {
        case .regular:   return "Regular item"
        case .sale:      return "Sale - was / now"
        case .clearance: return "End of season"
        case .used:      return "Part with fitment"
        case .apparel:   return "Boots & apparel"
        }
    }

    /// The text for the banner across the top of the sign, if this type has one.
    var banner: String? {
        switch self {
        case .sale:      return "SALE"
        case .clearance: return "END OF SEASON"
        case .used:      return "PRE-OWNED"
        default:         return nil
        }
    }
}

extension Sign {
    /// Whether this sign's type uses the Was price and % off at all. The editor
    /// shows those fields, and the sign face draws them, only when this is true.
    /// Stored values are kept when the type changes, so switching back restores them.
    var usesComparison: Bool {
        return type == .sale || type == .clearance || type == .used
    }

    /// The was-price that should print: empty unless this type uses one.
    var printedRegularPrice: String {
        return usesComparison ? regularPrice : ""
    }

    /// The percent-off that should print: empty unless this type uses one.
    var printedPercentOff: String {
        return usesComparison ? percentOff : ""
    }

    /// The flag actually printed. A parts sign only carries PRE-OWNED when it is
    /// marked as such, so the same layout covers new and used stock.
    var banner: String? {
        if type == .used { return markPreOwned ? "PRE-OWNED" : nil }
        return type.banner
    }
}

/// One printed sign.
///
/// A single struct holds every field any sign type might use.
/// Prices are stored as text because the app never does math on them.
struct Sign: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: SignType = .regular
    var brand: String = "Shoei"
    /// Which version of the brand mark to print, when that brand has more than one.
    var brandVariant: String?
    /// Where the logos sit across the top of the sign. Nil means automatic.
    var logoAlignment: LogoAlignment?
    var name: String = ""
    var variant: String = ""
    var size: String = ""
    var price: String = ""
    var cents: String = ""
    var regularPrice: String = ""
    var percentOff: String = ""
    var partNumber: String = ""
    var fitment: [String] = []
    /// Fitment as rows of models and years. Nil on signs saved before rows existed,
    /// which still print their `fitment` lines.
    var fitmentRows: [FitmentRow]?
    /// True when the part fits any model, so the strip says ALL MODELS.
    var universalFit: Bool?
    /// Parts signs only: true when this sign prints on a landscape sheet (two to a
    /// sideways sheet). Nil means the usual four to a sheet. Not saved to the Library.
    var landscape: Bool?
    var condition: String = ""
    /// Parts signs print the PRE-OWNED flag only when this is on.
    var markPreOwned: Bool = true
    var note: String = ""
    var featureLogos: [String] = []
    var splitCents: Bool = true
    /// The Library entry this sign was saved to or added from, so saving again
    /// updates that entry instead of adding another copy.
    var libraryID: UUID?
    /// When this sign was saved to the Library, for sorting. Nil on older saves.
    var savedAt: Date?
    /// Only read once, to move stars saved by earlier versions into the favourites
    /// list on the Store. Favourites are personal, so they no longer live on the sign.
    var isFavourite: Bool?
    /// Where the banner prints. Nil means automatic: beside the brand until that squeezes the brand too far, then beside the % OFF flag.
    var bannerSpot: MarkSpot?
    /// Library entries only: the account that made the entry. Nil on entries saved
    /// before accounts existed; those belong to the admin.
    var createdBy: String?
    /// Library entries only: true for a copy that only its owner sees and uses.
    var isPersonal: Bool?
    /// Library entries only: the shared entry a personal copy was made from, so
    /// its owner can ask for the shared sign to be updated.
    var basedOn: UUID?
}

/// Where the brand logo, feature logos and banner sit in the header row.
enum LogoAlignment: String, Codable, CaseIterable {
    /// Centred over the product name, but never further in than centred in the logo's slot.
    case auto
    /// Flush with the left edge of the text.
    case left

    /// Anything unknown, such as a value from an earlier version, reads as automatic.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LogoAlignment(rawValue: raw) ?? .auto
    }
}

/// A placement choice for the banner.
enum MarkSpot: String, Codable, CaseIterable {
    case auto
    case header
    case side
}

/// What saving a sign to the Library did.
enum LibrarySaveResult {
    /// A new shared entry.
    case saved
    /// An entry this account may change was updated.
    case updated
    /// The shared entry belongs to someone else, so the changes went into a personal
    /// copy. The shared sign changes only when its maker or an admin approves.
    case savedPersonal
}

// MARK: Accounts and sharing
//
// There is no sign-in yet. Everything runs as one local admin account, but the
// Library already asks these rules before it changes anything, so adding real
// accounts later means supplying `Store.account` and nothing else.

enum Role: String, Codable {
    case admin
    case member
}

struct Account: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var role: Role

    /// The account used until sign-in exists.
    static let local = Account(id: "local", name: "You", role: .admin)

    var isAdmin: Bool { return role == .admin }

    /// Stand-ins for testing sharing without sign-in: the admin and two members.
    static let testAccounts: [Account] = [
        .local,
        Account(id: "test-sam", name: "Sam", role: .member),
        Account(id: "test-alex", name: "Alex", role: .member)
    ]
}

/// Who may do what to a Library entry. Every Library change goes through here.
enum LibraryRights {
    /// Personal copies are private to the account that made them.
    static func canSee(_ entry: Sign, _ account: Account) -> Bool {
        return entry.isPersonal != true || entry.createdBy == account.id
    }

    /// The maker of an entry and any admin can change it for everyone.
    static func canUpdateDirectly(_ entry: Sign, _ account: Account) -> Bool {
        return account.isAdmin || entry.createdBy == account.id
    }

    /// Admins delete shared entries. People delete their own personal copies.
    static func canDeleteDirectly(_ entry: Sign, _ account: Account) -> Bool {
        if entry.isPersonal == true { return entry.createdBy == account.id }
        return account.isAdmin
    }

    /// Update requests go to the maker of the entry or an admin; deletions to an admin.
    static func canApprove(_ request: LibraryRequest, entry: Sign?, _ account: Account) -> Bool {
        switch request.kind {
        case .delete: return account.isAdmin
        case .update: return account.isAdmin || entry?.createdBy == account.id
        }
    }
}

/// Someone asking for a change to a shared entry that they are not allowed to make.
struct LibraryRequest: Codable, Identifiable {
    enum Kind: String, Codable {
        case update
        case delete
    }

    var id: UUID = UUID()
    var kind: Kind
    /// The shared entry the request is about.
    var entryID: UUID
    /// For an update, the new version of the sign.
    var proposed: Sign?
    /// For an update, the requester's personal copy that holds those changes.
    var copyID: UUID?
    var requestedBy: String
    var requestedByName: String
    var requestedAt: Date = Date()
}

/// The three linked price fields on a sale-style sign.
enum PriceField: Hashable {
    case was
    case percent
    case price
}

extension Sign {
    /// The text stored in one of the three linked price fields.
    func text(for field: PriceField) -> String {
        switch field {
        case .was:     return regularPrice
        case .percent: return percentOff
        case .price:   return price
        }
    }

    mutating func setText(_ value: String, for field: PriceField) {
        switch field {
        case .was:     regularPrice = value
        case .percent: percentOff = value
        case .price:   price = value
        }
    }
}

/// Works out the third of Was / % off / Price from the other two.
///
/// The three always satisfy  price = was × (1 − percent ÷ 100).  Decimal keeps
/// amounts like 1309.95 exact. Every function returns nil when the inputs can't
/// produce a sensible number, so the editor simply offers nothing.
enum PriceSuggestion {

    /// The value for `field`, worked out from the other two.
    static func suggestion(for field: PriceField, was: String, percent: String, price: String) -> String? {
        switch field {
        case .was:     return deriveWas(price: price, percent: percent)
        case .percent: return derivePercent(was: was, price: price)
        case .price:   return derivePrice(was: was, percent: percent)
        }
    }

    /// New price from the old price and the discount. Dropped to the cent and
    /// never rounded up, so the price is never higher than the percent promises.
    static func derivePrice(was: String, percent: String) -> String? {
        guard let w = amount(was), let p = amount(percent), p < 100 else { return nil }
        let result = roundDecimal(w * (100 - p) / 100, scale: 2, mode: .down)
        return result > 0 ? money(result) : nil
    }

    /// Whole-number discount from the old and new price. Rounded down with a
    /// 0.05 tolerance, so 9.997% reads as 10 but 9.9% reads as 9 and the sign
    /// never promises more than it gives.
    static func derivePercent(was: String, price: String) -> String? {
        guard let w = amount(was), let x = amount(price), x < w else { return nil }
        let tolerance = Decimal(sign: .plus, exponent: -2, significand: 5)
        let whole = roundDecimal((w - x) / w * 100 + tolerance, scale: 0, mode: .down)
        guard whole >= 1 else { return nil }
        return String(NSDecimalNumber(decimal: whole).intValue)
    }

    /// Old price from the new price and the discount, to the nearest cent.
    /// Approximate: the new price was probably cut to the cent, so this can be
    /// a cent off the real old price.
    static func deriveWas(price: String, percent: String) -> String? {
        guard let x = amount(price), let p = amount(percent), p < 100 else { return nil }
        return money(roundDecimal(x * 100 / (100 - p), scale: 2, mode: .plain))
    }

    /// Reads typed text as a positive number. Nil for empty, zero or non-numeric text.
    static func amount(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    private static func roundDecimal(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, mode)
        return output
    }

    private static func money(_ value: Decimal) -> String {
        return String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}

/// A page of signs: four to a sheet, or two on a sideways sheet, as many sheets as it needs.
struct SignPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "Untitled page"
    var signs: [Sign] = []

    /// The signs in groups, one group per printed sheet.
    var sheets: [[Sign]] { return sheetChunks(signs) }
}

extension Sign {
    /// True when this sign prints on a landscape sheet. Only Parts signs have that layout.
    var onLandscapeSheet: Bool { return landscape == true && type == .used }
}

extension URL: Identifiable {
    public var id: String { return absoluteString }
}
