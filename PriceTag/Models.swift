//
//  Models.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-13.
//

import Foundation

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
        case .clearance: return "Clearance"
        case .used:      return "Part with fitment"
        case .apparel:   return "Boots & apparel"
        }
    }

    var banner: String? {
        switch self {
        case .sale:      return "SALE"
        case .clearance: return "CLEARANCE"
        case .used:      return "PRE-OWNED"
        default:         return nil
        }
    }
}

extension Sign {
    /// The flag actually printed. A parts sign only carries PRE-OWNED when it is
    /// marked as such, so the same layout covers new and used stock.
    var banner: String? {
        if type == .used { return markPreOwned ? "PRE-OWNED" : nil }
        return type.banner
    }
}

struct Sign: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: SignType = .regular
    var brand: String = "Shoei"
    /// Which version of the brand mark to print, when that brand has more than one.
    var brandVariant: String?
    var name: String = ""
    var variant: String = ""
    var size: String = ""
    var price: String = ""
    var cents: String = ""
    var regularPrice: String = ""
    var percentOff: String = ""
    var partNumber: String = ""
    var fitment: [String] = []
    var condition: String = ""
    /// Parts signs print the PRE-OWNED flag only when this is on.
    var markPreOwned: Bool = true
    var note: String = ""
    var featureLogos: [String] = []
    var splitCents: Bool = true
}

struct SignPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "Untitled page"
    var signs: [Sign] = []
}

extension URL: Identifiable {
    public var id: String { return absoluteString }
}
