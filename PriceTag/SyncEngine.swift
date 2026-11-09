//
//  SyncEngine.swift
//  PriceTag
//
//  Keeps this phone's Library in step with the shared one online.
//
//  The app still works from its own file and never waits on the network. Every few
//  seconds after a change (and when the app opens or comes forward) this sends what
//  changed here, then fetches what changed elsewhere. What the server will accept is
//  decided by its own rules (backend/sql/002_rules.sql), not by this file.
//
//  How it tells what changed here: after every sync it remembers a fingerprint of each
//  sign as the server has it. A sign whose fingerprint differs has changed; a sign that
//  is gone from the Library but has a fingerprint was deleted.
//

import SwiftUI
import Combine
import CryptoKit

/// What the phone remembers between syncs. Saved inside the Library file.
///
/// Reading is forgiving on purpose: a file saved by an earlier version has fewer fields,
/// and failing to read it would look like an empty Library.
struct SyncState: Codable, Equatable {
    /// The account this phone's synced content belongs to.
    var userID: String?
    /// The newest server change already fetched, in seconds since 1970.
    var cursor: Double?
    /// A fingerprint of each Library entry as the server has it, by ID.
    var signHashes: [String: String] = [:]
    /// Favourites the server knows about.
    var favourites: [String] = []
    /// Requests the server already has (or has already decided).
    var pushedRequests: [String] = []
    /// The same two, for Pages.
    var pageCursor: Double?
    var pageHashes: [String: String] = [:]
    /// Logos that are in step with the server, by this phone's ID for the logo.
    var logos: [String: LogoMark] = [:]
    var logoCursor: Double?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try? c.decodeIfPresent(String.self, forKey: .userID)
        cursor = try? c.decodeIfPresent(Double.self, forKey: .cursor)
        signHashes = (try? c.decodeIfPresent([String: String].self, forKey: .signHashes)) ?? [:]
        favourites = (try? c.decodeIfPresent([String].self, forKey: .favourites)) ?? []
        pushedRequests = (try? c.decodeIfPresent([String].self, forKey: .pushedRequests)) ?? []
        pageCursor = try? c.decodeIfPresent(Double.self, forKey: .pageCursor)
        pageHashes = (try? c.decodeIfPresent([String: String].self, forKey: .pageHashes)) ?? [:]
        logos = (try? c.decodeIfPresent([String: LogoMark].self, forKey: .logos)) ?? [:]
        logoCursor = try? c.decodeIfPresent(Double.self, forKey: .logoCursor)
    }
}

/// What the phone knew about one shared logo the last time it was in step with the server.
struct LogoMark: Codable, Equatable {
    /// The server's ID for the logo.
    var serverID: String
    var kind: String
    var name: String
    /// The version label ("Parts"), empty for none.
    var variant: String
    /// Goes up by one each time an admin changes the logo.
    var version: Int
    /// `LogoLibrary.artworkStamp` of the artwork on this phone when last in step.
    var stamp: String
}

// MARK: - Turning signs into rows and back

enum SignCodec {
    /// Facts that live in their own columns, so they are not kept inside the JSON.
    private static let columnKeys = ["id", "createdBy", "isPersonal", "basedOn", "libraryID"]

    /// Everything about a sign, as the app saves it.
    static func fullObject(_ sign: Sign) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(sign),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return object
    }

    /// What goes in the `data` column.
    static func dataObject(_ sign: Sign) -> [String: Any] {
        var object = fullObject(sign)
        for key in columnKeys { object.removeValue(forKey: key) }
        return object
    }

    /// A sign from a `signs` row.
    static func sign(from row: [String: Any]) -> Sign? {
        guard var object = row["data"] as? [String: Any],
              let id = row["id"] as? String else { return nil }
        object["id"] = id
        object.removeValue(forKey: "libraryID")
        if let maker = row["created_by"] as? String { object["createdBy"] = maker }
        if (row["is_personal"] as? Bool) == true { object["isPersonal"] = true }
        if let base = row["based_on"] as? String { object["basedOn"] = base }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(Sign.self, from: data)
    }

    /// A sign from a whole-sign JSON object, such as a request's proposed version.
    static func sign(fromObject object: [String: Any]) -> Sign? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(Sign.self, from: data)
    }

    /// A short fingerprint: equal signs give equal text.
    static func hash(_ sign: Sign) -> String {
        var normal = sign
        if normal.isPersonal == false { normal.isPersonal = nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(normal)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Turning Pages into rows and back

enum PageCodec {
    /// The `data` column: everything but the ID, which has its own column.
    static func dataObject(_ page: SignPage) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(page),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        object.removeValue(forKey: "id")
        return object
    }

    static func page(from row: [String: Any]) -> SignPage? {
        guard var object = row["data"] as? [String: Any], let id = row["id"] as? String else { return nil }
        object["id"] = id
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(SignPage.self, from: data)
    }

    static func hash(_ page: SignPage) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(page)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Server times

enum ServerTime {
    /// Reads times like 2026-11-09T15:12:34.123456+00:00.
    static func parse(_ raw: String) -> Date? {
        var text = raw.replacingOccurrences(of: " ", with: "T")
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            var end = text.index(after: dot)
            while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
            let digits = String(text[text.index(after: dot)..<end])
            fraction = Double("0." + digits) ?? 0
            text.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let base = formatter.date(from: text) else { return nil }
        return base.addingTimeInterval(fraction)
    }

    /// Text the server accepts in a filter, with no "+" to be mistaken for a space.
    static func text(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - The engine

@MainActor
final class SyncEngine: ObservableObject {

    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case problem(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSynced: Date?

    private let store: Store
    private let auth: AuthStore

    private var applying = false
    private var running = false
    private var again = false
    private var debounce: Task<Void, Never>?
    private var problems: [String] = []
    private var lastRefusal = ""
    private var names: [String: String] = [:]

    init(store: Store, auth: AuthStore) {
        self.store = store
        self.auth = auth
        store.onLocalChange = { [weak self] in self?.localChanged() }
        LogoLibrary.shared.onChange = { [weak self] in self?.localChanged() }
    }

    // MARK: Connecting

    /// Called whenever the sign-in state changes.
    func authChanged(_ state: AccountState) {
        switch state {
        case .active(let account):
            connect(account)
        case .removed:
            // Access was taken away: the shared Library leaves this phone.
            if store.isConnected || store.syncState.userID != nil {
                store.clearSharedContent()
            }
        case .signedOut, .pending:
            // Stop syncing but keep what is here, in case the same person signs back in.
            store.disconnect()
        case .unknown:
            break
        }
    }

    private func connect(_ account: Account) {
        if let previous = store.syncState.userID, previous != account.id {
            // Someone else's content must not be sent under this account.
            store.clearSharedContent()
        }
        store.account = account
        if store.syncState.userID != account.id {
            store.claimLocalContent(for: account)
        }
        // Anything still unclaimed (such as signs made under the test accounts) is theirs too.
        store.claimLeftovers(for: account)
        store.remote = self
        store.isConnected = true
        Task { await sync() }
    }

    // MARK: Triggers

    /// A change was made here: send it shortly, once the person has stopped editing.
    private func localChanged() {
        guard store.isConnected, !applying else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await self?.sync()
        }
    }

    /// Syncs now. Safe to call at any time; overlapping calls are folded into one.
    func sync() async {
        guard store.isConnected else { return }
        if running {
            again = true
            return
        }
        running = true
        status = .syncing
        defer { running = false }

        var rounds = 0
        repeat {
            again = false
            rounds += 1
            // A follow-up round keeps what the first one had to report.
            if rounds == 1 { problems = [] }
            do {
                try await runOnce()
                lastSynced = Date()
                status = problems.isEmpty ? .idle : .problem(problems.joined(separator: " "))
            } catch is CancellationError {
                break
            } catch is URLError {
                status = .offline
                break
            } catch let error as BackendError {
                status = .problem(error.text)
                break
            } catch {
                status = .problem("Something went wrong while syncing.")
                break
            }
        } while again && rounds < 3
    }

    /// How many changes are waiting to be sent.
    var pendingChanges: Int {
        let hashes = store.syncState.signHashes
        let present = Set(store.library.map { $0.id.uuidString })
        var count = 0
        for entry in store.library where hashes[entry.id.uuidString] != SignCodec.hash(entry) {
            // A new sign made under another account can never be sent from here.
            if hashes[entry.id.uuidString] == nil && entry.createdBy != store.account.id { continue }
            count += 1
        }
        count += hashes.keys.filter { !present.contains($0) }.count
        let pushed = Set(store.syncState.pushedRequests)
        count += store.requests.filter { !pushed.contains($0.id.uuidString) }.count
        let pageHashes = store.syncState.pageHashes
        let pagesHere = Set(store.pages.map { $0.id.uuidString })
        count += store.pages.filter { pageHashes[$0.id.uuidString] != PageCodec.hash($0) }.count
        count += pageHashes.keys.filter { !pagesHere.contains($0) }.count
        count += logoChanges
        return count
    }

    /// Signs out. Sends what is waiting first; if some of it could not be sent, stops and
    /// returns false so the person can choose to sign out anyway.
    func signOut(force: Bool = false) async -> Bool {
        if !force {
            await sync()
            if pendingChanges > 0 { return false }
        }
        store.clearSharedContent()
        await auth.signOut()
        return true
    }

    /// Approves or declines a request on the server, then refreshes.
    func decide(_ request: LibraryRequest, approve: Bool) async {
        do {
            _ = try await call("POST", "/rest/v1/rpc/" + (approve ? "approve_request" : "decline_request"),
                               json: ["p_request": request.id.uuidString.lowercased()])
            await sync()
        } catch let error as BackendError {
            status = .problem(error.text)
        } catch {
            status = .offline
        }
    }

    // MARK: One round

    private func runOnce() async throws {
        let account = store.account
        try await pushSigns(account)
        try await pushRequests(account)
        try await pushFavourites(account)
        try await pushPages(account)
        try await pullPeople()
        try await pullSigns()
        try await pullRequests()
        try await pullFavourites(account)
        try await pullPages(account)
        // Logos last, and fetched before sending, so a logo that is already shared is
        // recognised by name instead of being added a second time.
        try await pullLogos()
        try await pushLogos(account)
    }

    // MARK: Talking to the server

    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [],
                      json: Any? = nil, prefer: String? = nil) async throws -> Data {
        var body: Data?
        if let json = json { body = try JSONSerialization.data(withJSONObject: json) }
        var headers: [String: String] = [:]
        if let prefer = prefer { headers["Prefer"] = prefer }
        return try await auth.call(method, path, query: query, bodyData: body, headers: headers)
    }

    private func rows(_ data: Data) -> [[String: Any]] {
        return ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? []
    }

    private var business: URLQueryItem {
        return URLQueryItem(name: "business_id", value: "eq." + Backend.businessID)
    }

    /// An update that returns the rows it changed. Zero rows back means the server refused
    /// or hid it; the reason is kept in `lastRefusal`. Only network failures throw.
    private func patchSigns(_ filters: [URLQueryItem], _ body: [String: Any]) async throws -> [[String: Any]] {
        return try await patchRows("signs", filters, body)
    }

    private func patchRows(_ table: String, _ filters: [URLQueryItem], _ body: [String: Any]) async throws -> [[String: Any]] {
        do {
            let data = try await call("PATCH", "/rest/v1/" + table, query: filters + [business],
                                      json: body, prefer: "return=representation")
            return rows(data)
        } catch let error as BackendError {
            lastRefusal = error.text
            return []
        }
    }

    private func idFilter(_ id: String) -> URLQueryItem {
        return URLQueryItem(name: "id", value: "eq." + id.lowercased())
    }

    // MARK: Pushing signs

    private func pushSigns(_ account: Account) async throws {
        let present = Set(store.library.map { $0.id.uuidString })

        // Removed here, so removed there.
        for key in Array(store.syncState.signHashes.keys) where !present.contains(key) {
            try await pushDeletion(key)
        }

        // New and changed. Shared signs first, so a personal copy's original exists before it.
        let ordered = store.library.filter { $0.isPersonal != true } + store.library.filter { $0.isPersonal == true }
        for entry in ordered {
            let key = entry.id.uuidString
            let hash = SignCodec.hash(entry)
            let known = store.syncState.signHashes[key] != nil
            if store.syncState.signHashes[key] == hash { continue }
            if !known && entry.createdBy != account.id { continue }
            try await pushSign(entry, known: known, hash: hash, account: account)
        }
    }

    private func pushDeletion(_ key: String) async throws {
        lastRefusal = ""
        let changed = try await patchSigns([idFilter(key)], ["deleted_at": ServerTime.text(Date())])
        store.syncState.signHashes[key] = nil
        if changed.isEmpty {
            // Not allowed, or not there. If the server still has it, the server wins.
            if await reconcile(key) {
                problems.append("A deletion was not allowed and was undone.")
            }
        }
    }

    private func pushSign(_ entry: Sign, known: Bool, hash: String, account: Account) async throws {
        let key = entry.id.uuidString
        let object = SignCodec.dataObject(entry)
        lastRefusal = ""

        if !known {
            var row: [String: Any] = [
                "id": key.lowercased(),
                "business_id": Backend.businessID,
                "created_by": account.id,
                "is_personal": entry.isPersonal == true,
                "data": object
            ]
            if let base = entry.basedOn { row["based_on"] = base.uuidString.lowercased() }
            do {
                _ = try await call("POST", "/rest/v1/signs", json: row, prefer: "return=minimal")
                store.syncState.signHashes[key] = hash
                return
            } catch let error as BackendError {
                if error.text.contains("foreign key") {
                    // The sign this was copied from is gone. Keep this one on its own.
                    if let i = store.library.firstIndex(where: { $0.id == entry.id }) {
                        store.library[i].basedOn = nil
                        again = true
                    }
                    return
                }
                if !error.text.contains("duplicate key") {
                    problems.append("\(entry.name.isEmpty ? "A sign" : entry.name) could not be saved online: \(error.text)")
                    return
                }
                // Already there: fall through and update it.
            }
        }

        let changed = try await patchSigns([idFilter(key)], ["data": object])
        if !changed.isEmpty {
            store.syncState.signHashes[key] = hash
        } else if known {
            _ = await reconcile(key)
            problems.append("A change to \(entry.name.isEmpty ? "a sign" : entry.name) was not allowed, so it went back to the shared version.")
        } else {
            // That ID belongs to somebody else's sign. Keep this as a personal copy under its own ID.
            if let i = store.library.firstIndex(where: { $0.id == entry.id }) {
                var copy = store.library[i]
                copy.id = UUID()
                copy.isPersonal = true
                copy.basedOn = nil
                store.library[i] = copy
                again = true
            }
        }
    }

    /// Fetches one sign from the server and takes its version. True if the server has it.
    private func reconcile(_ key: String) async -> Bool {
        guard let data = try? await call("GET", "/rest/v1/signs", query: [idFilter(key), business]) else { return false }
        let found = rows(data).filter { !($0["deleted_at"] is String) }
        guard !found.isEmpty else { return false }
        applySigns(found, serverWins: true)
        return true
    }

    // MARK: Pushing requests and favourites

    private func pushRequests(_ account: Account) async throws {
        let pushed = Set(store.syncState.pushedRequests)
        let hashes = store.syncState.signHashes
        for request in store.requests where !pushed.contains(request.id.uuidString) && request.requestedBy == account.id {
            guard hashes[request.entryID.uuidString] != nil else { continue }
            var row: [String: Any] = [
                "id": request.id.uuidString.lowercased(),
                "business_id": Backend.businessID,
                "kind": request.kind.rawValue,
                "sign_id": request.entryID.uuidString.lowercased(),
                "requested_by": account.id
            ]
            if request.kind == .update {
                guard let copy = request.copyID, hashes[copy.uuidString] != nil,
                      let proposed = request.proposed else { continue }
                row["copy_id"] = copy.uuidString.lowercased()
                row["proposed"] = SignCodec.fullObject(proposed)
            }
            do {
                _ = try await call("POST", "/rest/v1/requests", json: row, prefer: "return=minimal")
                store.syncState.pushedRequests.append(request.id.uuidString)
            } catch let error as BackendError {
                if error.text.contains("duplicate key") {
                    store.syncState.pushedRequests.append(request.id.uuidString)
                } else {
                    // The server will not take it, so it goes no further.
                    store.requests.removeAll { $0.id == request.id }
                    problems.append("A request was not accepted: \(error.text)")
                }
            }
        }
    }

    private func pushFavourites(_ account: Account) async throws {
        let local = Set(store.favouriteIDs.map { $0.uuidString })
        var synced = Set(store.syncState.favourites)
        let hashes = store.syncState.signHashes

        for id in local.subtracting(synced) where hashes[id] != nil {
            do {
                _ = try await call("POST", "/rest/v1/favourites",
                                   json: ["user_id": account.id, "business_id": Backend.businessID, "sign_id": id.lowercased()],
                                   prefer: "resolution=ignore-duplicates,return=minimal")
                synced.insert(id)
            } catch is BackendError {
                // Not a sign the server lets this person star; leave it local.
            }
        }
        for id in synced.subtracting(local) {
            do {
                _ = try await call("DELETE", "/rest/v1/favourites", query: [
                    URLQueryItem(name: "user_id", value: "eq." + account.id),
                    URLQueryItem(name: "sign_id", value: "eq." + id.lowercased())
                ])
                synced.remove(id)
            } catch is BackendError {
                synced.remove(id)
            }
        }
        store.syncState.favourites = Array(synced)
    }

    // MARK: Pages

    private func pushPages(_ account: Account) async throws {
        let present = Set(store.pages.map { $0.id.uuidString })

        // Deleted here, so moved to the Trash there.
        for key in Array(store.syncState.pageHashes.keys) where !present.contains(key) {
            _ = try await patchRows("pages", [idFilter(key)], ["deleted_at": ServerTime.text(Date())])
            store.syncState.pageHashes[key] = nil
        }

        for page in store.pages {
            let key = page.id.uuidString
            let hash = PageCodec.hash(page)
            if store.syncState.pageHashes[key] == hash { continue }
            let known = store.syncState.pageHashes[key] != nil
            let object = PageCodec.dataObject(page)

            if !known {
                let row: [String: Any] = [
                    "id": key.lowercased(),
                    "business_id": Backend.businessID,
                    "owner_id": account.id,
                    "data": object
                ]
                do {
                    _ = try await call("POST", "/rest/v1/pages", json: row, prefer: "return=minimal")
                    store.syncState.pageHashes[key] = hash
                    continue
                } catch let error as BackendError {
                    if !error.text.contains("duplicate key") {
                        problems.append("A page could not be saved online: \(error.text)")
                        continue
                    }
                    // Already there: fall through and update it.
                }
            }

            lastRefusal = ""
            let changed = try await patchRows("pages", [idFilter(key)], ["data": object])
            if !changed.isEmpty {
                store.syncState.pageHashes[key] = hash
            } else if !known, let i = store.pages.firstIndex(where: { $0.id == page.id }) {
                // That ID belongs to somebody else's page. Keep this one under its own ID.
                var copy = store.pages[i]
                copy.id = UUID()
                store.pages[i] = copy
                again = true
            } else {
                problems.append("A page could not be updated online: \(lastRefusal)")
            }
        }
    }

    private func pullPages(_ account: Account) async throws {
        var since: String? = store.syncState.pageCursor.map { ServerTime.text(Date(timeIntervalSince1970: $0 - 10)) }
        var newest = store.syncState.pageCursor ?? 0
        let pageSize = 500

        while true {
            var query = [
                URLQueryItem(name: "select", value: "id,data,updated_at,deleted_at"),
                URLQueryItem(name: "owner_id", value: "eq." + account.id),
                URLQueryItem(name: "order", value: "updated_at.asc"),
                URLQueryItem(name: "limit", value: String(pageSize))
            ]
            if let since = since {
                query.append(URLQueryItem(name: "updated_at", value: "gt." + since))
            } else {
                query.append(URLQueryItem(name: "deleted_at", value: "is.null"))
            }
            let data = try await call("GET", "/rest/v1/pages", query: query)
            let batch = rows(data)
            applyPages(batch)
            for row in batch {
                if let text = row["updated_at"] as? String, let date = ServerTime.parse(text) {
                    newest = max(newest, date.timeIntervalSince1970)
                }
            }
            guard batch.count >= pageSize, let last = batch.last?["updated_at"] as? String else { break }
            since = last.replacingOccurrences(of: "+00:00", with: "Z")
        }
        if newest > 0 { store.syncState.pageCursor = newest }
    }

    private func applyPages(_ batch: [[String: Any]]) {
        applying = true
        defer { applying = false }

        for row in batch {
            guard let text = row["id"] as? String, let id = UUID(uuidString: text) else { continue }
            let key = id.uuidString
            let index = store.pages.firstIndex { $0.id == id }

            if row["deleted_at"] is String {
                if let i = index { store.pages.remove(at: i) }
                store.syncState.pageHashes[key] = nil
                continue
            }
            guard let incoming = PageCodec.page(from: row) else { continue }
            let incomingHash = PageCodec.hash(incoming)

            if let i = index {
                let localHash = PageCodec.hash(store.pages[i])
                if localHash == incomingHash {
                    store.syncState.pageHashes[key] = incomingHash
                    continue
                }
                // A change made here and not sent yet keeps this phone's version.
                if let synced = store.syncState.pageHashes[key], localHash != synced { continue }
                store.pages[i] = incoming
            } else {
                store.pages.append(incoming)
            }
            store.syncState.pageHashes[key] = incomingHash
        }
    }

    // MARK: Pulling

    private func pullPeople() async throws {
        let data = try await call("GET", "/rest/v1/members", query: [
            URLQueryItem(name: "select", value: "user_id,name"), business
        ])
        var map: [String: String] = [:]
        for row in rows(data) {
            if let id = row["user_id"] as? String, let name = row["name"] as? String { map[id] = name }
        }
        names = map
    }

    private func pullSigns() async throws {
        var since: String? = store.syncState.cursor.map { ServerTime.text(Date(timeIntervalSince1970: $0 - 10)) }
        var newest = store.syncState.cursor ?? 0
        let pageSize = 500

        while true {
            var query = [
                URLQueryItem(name: "select", value: "id,created_by,is_personal,based_on,data,updated_at,deleted_at"),
                business,
                URLQueryItem(name: "order", value: "updated_at.asc"),
                URLQueryItem(name: "limit", value: String(pageSize))
            ]
            if let since = since {
                query.append(URLQueryItem(name: "updated_at", value: "gt." + since))
            } else {
                // First time here: no need for anything already deleted.
                query.append(URLQueryItem(name: "deleted_at", value: "is.null"))
            }
            let data = try await call("GET", "/rest/v1/signs", query: query)
            let page = rows(data)
            applySigns(page, serverWins: false)
            for row in page {
                if let text = row["updated_at"] as? String, let date = ServerTime.parse(text) {
                    newest = max(newest, date.timeIntervalSince1970)
                }
            }
            guard page.count >= pageSize, let last = page.last?["updated_at"] as? String else { break }
            since = last.replacingOccurrences(of: "+00:00", with: "Z")
        }
        if newest > 0 { store.syncState.cursor = newest }
    }

    /// Takes in rows from the server. A sign changed here and not yet sent keeps this
    /// phone's version (it is sent next), unless the server's is to win.
    private func applySigns(_ page: [[String: Any]], serverWins: Bool) {
        applying = true
        defer { applying = false }

        for row in page {
            guard let text = row["id"] as? String, let id = UUID(uuidString: text) else { continue }
            let key = id.uuidString
            let index = store.library.firstIndex { $0.id == id }

            if row["deleted_at"] is String {
                if let i = index { store.library.remove(at: i) }
                store.forgetDeleted(id)
                store.syncState.signHashes[key] = nil
                continue
            }
            guard let incoming = SignCodec.sign(from: row) else { continue }
            let incomingHash = SignCodec.hash(incoming)

            if let i = index {
                let localHash = SignCodec.hash(store.library[i])
                if localHash == incomingHash {
                    store.syncState.signHashes[key] = incomingHash
                    continue
                }
                if !serverWins, let synced = store.syncState.signHashes[key], localHash != synced {
                    continue
                }
                store.library[i] = incoming
            } else {
                store.library.append(incoming)
            }
            store.syncState.signHashes[key] = incomingHash
        }
    }

    private func pullRequests() async throws {
        let data = try await call("GET", "/rest/v1/requests", query: [
            URLQueryItem(name: "select", value: "id,kind,sign_id,copy_id,proposed,requested_by,created_at"),
            URLQueryItem(name: "status", value: "eq.open"),
            business
        ])
        var fromServer: [LibraryRequest] = []
        for row in rows(data) {
            guard let idText = row["id"] as? String, let id = UUID(uuidString: idText),
                  let kindText = row["kind"] as? String, let kind = LibraryRequest.Kind(rawValue: kindText),
                  let signText = row["sign_id"] as? String, let signID = UUID(uuidString: signText),
                  let by = row["requested_by"] as? String else { continue }
            var proposed: Sign?
            if let object = row["proposed"] as? [String: Any] { proposed = SignCodec.sign(fromObject: object) }
            var copy: UUID?
            if let copyText = row["copy_id"] as? String { copy = UUID(uuidString: copyText) }
            let made = (row["created_at"] as? String).flatMap { ServerTime.parse($0) } ?? Date()
            fromServer.append(LibraryRequest(
                id: id, kind: kind, entryID: signID, proposed: proposed, copyID: copy,
                requestedBy: by, requestedByName: names[by] ?? "Someone", requestedAt: made))
        }

        let serverIDs = Set(fromServer.map { $0.id.uuidString })
        let pushed = Set(store.syncState.pushedRequests)
        // Requests made here and not sent yet stay; everything else is what the server says.
        let waiting = store.requests.filter {
            !pushed.contains($0.id.uuidString) && !serverIDs.contains($0.id.uuidString)
        }
        applying = true
        store.requests = fromServer + waiting
        applying = false
        store.syncState.pushedRequests = Array(serverIDs)
    }

    private func pullFavourites(_ account: Account) async throws {
        let local = Set(store.favouriteIDs.map { $0.uuidString })
        // Changes still waiting to be sent must not be overwritten.
        guard local == Set(store.syncState.favourites) else { return }

        let data = try await call("GET", "/rest/v1/favourites", query: [
            URLQueryItem(name: "select", value: "sign_id"),
            URLQueryItem(name: "user_id", value: "eq." + account.id)
        ])
        let ids = Set(rows(data).compactMap { ($0["sign_id"] as? String).flatMap { UUID(uuidString: $0) } })
        applying = true
        store.favouriteIDs = ids
        applying = false
        store.syncState.favourites = ids.map { $0.uuidString }
    }

    // MARK: Logos

    /// How many logo changes are waiting to be sent.
    private var logoChanges: Int {
        let library = LogoLibrary.shared
        let marks = store.syncState.logos
        let present = Set(library.assets.map { $0.id.uuidString })
        var count = marks.keys.filter { !present.contains($0) }.count
        for asset in library.assets {
            if let mark = marks[asset.id.uuidString] {
                if library.artworkStamp(id: asset.id) != mark.stamp || !matches(mark, asset) { count += 1 }
            } else if asset.hasImage {
                count += 1
            }
        }
        return count
    }

    /// Adds a message for the person once, even if two rounds run into the same thing.
    private func report(_ text: String) {
        if !problems.contains(text) { problems.append(text) }
    }

    private func matches(_ mark: LogoMark, _ asset: LogoAsset) -> Bool {
        return mark.kind == asset.kind.rawValue && mark.name == asset.name && mark.variant == asset.variantLabel
    }

    /// Adds a picture to the logo storage and returns where it went.
    private func uploadLogo(_ data: Data, logoID: String) async throws -> String {
        let path = Backend.businessID + "/" + logoID + "/" + UUID().uuidString.lowercased() + ".png"
        _ = try await auth.call("POST", "/storage/v1/object/logos/" + path,
                                bodyData: data, headers: ["Content-Type": "image/png"])
        return path
    }

    private func downloadLogo(_ path: String) async throws -> Data {
        return try await auth.call("GET", "/storage/v1/object/authenticated/logos/" + path)
    }

    private func logoProblem(_ error: BackendError, name: String) -> String {
        if error.text.lowercased().contains("bucket not found") {
            return "Logo storage is not set up online yet (run 004_logo_storage.sql)."
        }
        return "The logo \(name) could not be shared: \(error.text)"
    }

    private func pullLogos() async throws {
        let fullPull = store.syncState.logoCursor == nil
        var since: String? = store.syncState.logoCursor.map { ServerTime.text(Date(timeIntervalSince1970: $0 - 10)) }
        var newest = store.syncState.logoCursor ?? 0
        var complete = true
        var seen = Set<String>()
        let pageSize = 200

        while true {
            var query = [
                URLQueryItem(name: "select", value: "id,kind,name,variant,file_path,version,updated_at,deleted_at"),
                business,
                URLQueryItem(name: "order", value: "updated_at.asc"),
                URLQueryItem(name: "limit", value: String(pageSize))
            ]
            if let since = since {
                query.append(URLQueryItem(name: "updated_at", value: "gt." + since))
            } else {
                query.append(URLQueryItem(name: "deleted_at", value: "is.null"))
            }
            let data = try await call("GET", "/rest/v1/logos", query: query)
            let page = rows(data)
            let fetched = try await applyLogos(page, seen: &seen)
            if !fetched { complete = false }
            for row in page {
                if let text = row["updated_at"] as? String, let date = ServerTime.parse(text) {
                    newest = max(newest, date.timeIntervalSince1970)
                }
            }
            guard page.count >= pageSize, let last = page.last?["updated_at"] as? String else { break }
            since = last.replacingOccurrences(of: "+00:00", with: "Z")
        }

        // Fetching everything: a logo this phone has as shared, which the server no longer
        // lists, was removed there.
        if fullPull && complete {
            let library = LogoLibrary.shared
            library.quiet = true
            for (key, mark) in store.syncState.logos where !seen.contains(mark.serverID) {
                if let id = UUID(uuidString: key) { library.remove(id) }
                store.syncState.logos[key] = nil
            }
            library.quiet = false
        }
        // Not moving on while a picture could not be fetched means the next sync tries again.
        if complete && newest > 0 { store.syncState.logoCursor = newest }
    }

    /// Takes in logo rows. Returns false if a picture could not be fetched.
    private func applyLogos(_ page: [[String: Any]], seen: inout Set<String>) async throws -> Bool {
        let library = LogoLibrary.shared
        library.quiet = true
        defer { library.quiet = false }
        var complete = true

        for row in page {
            guard let idText = row["id"] as? String else { continue }
            let serverID = idText.lowercased()
            let owner = store.syncState.logos.first { $0.value.serverID == serverID }

            if row["deleted_at"] is String {
                if let owner = owner {
                    if let id = UUID(uuidString: owner.key) { library.remove(id) }
                    store.syncState.logos[owner.key] = nil
                }
                continue
            }
            seen.insert(serverID)
            guard let kindText = row["kind"] as? String, let kind = LogoKind(rawValue: kindText),
                  let name = row["name"] as? String else { continue }
            let variant = (row["variant"] as? String) ?? ""
            let version = (row["version"] as? Int) ?? 1
            let filePath = row["file_path"] as? String

            // Which logo here is this one?
            let localID: UUID
            var mark: LogoMark? = owner?.value
            if let owner = owner, let id = UUID(uuidString: owner.key) {
                // Removed here and waiting to be sent: leave it be.
                guard library.asset(id: id) != nil else { continue }
                localID = id
            } else if let match = library.existing(kind: kind, name: name, variant: variant) {
                localID = match.id
                mark = nil
            } else {
                localID = UUID(uuidString: serverID) ?? UUID()
            }

            // Changed here and not sent yet, and the server has nothing newer: it goes next.
            if let known = mark, known.version == version, let here = library.asset(id: localID) {
                if library.artworkStamp(id: localID) != known.stamp || !matches(known, here) { continue }
            }

            library.applyShared(id: localID, kind: kind, name: name, variant: variant)
            if let path = filePath {
                let have = library.asset(id: localID)?.hasImage == true
                if mark?.version != version || !have {
                    do {
                        let data = try await downloadLogo(path)
                        if !library.setImage(data: data, for: localID) {
                            report("The artwork for \(name) could not be read.")
                            complete = false
                            continue
                        }
                    } catch let error as BackendError {
                        report(logoProblem(error, name: name))
                        complete = false
                        continue
                    }
                }
            } else if library.asset(id: localID)?.hasImage == true {
                library.clearImage(for: localID)
            }
            store.syncState.logos[localID.uuidString] = LogoMark(
                serverID: serverID, kind: kind.rawValue, name: name, variant: variant,
                version: version, stamp: library.artworkStamp(id: localID))
        }
        return complete
    }

    /// Sends this phone's logo changes. Anyone can share a new logo; only an admin can
    /// change or remove one that is already shared, and for anyone else such a change goes
    /// back to the shared version on the next round.
    private func pushLogos(_ account: Account) async throws {
        let library = LogoLibrary.shared
        let admin = account.isAdmin
        var failures: [String] = []

        // Fetch everything again next round and take the server's version.
        func goBack(_ key: String) {
            if var mark = store.syncState.logos[key] {
                mark.version = -1
                store.syncState.logos[key] = mark
            }
            store.syncState.logoCursor = nil
            again = true
        }

        // Removed here.
        let present = Set(library.assets.map { $0.id.uuidString })
        for (key, mark) in store.syncState.logos where !present.contains(key) {
            if admin {
                _ = try await patchRows("logos", [idFilter(mark.serverID)], ["deleted_at": ServerTime.text(Date())])
                store.syncState.logos[key] = nil
            } else {
                store.syncState.logos[key] = nil
                store.syncState.logoCursor = nil
                again = true
                report("Only an admin can delete a shared logo, so \(mark.name) came back.")
            }
        }

        // New and changed.
        for asset in library.assets {
            let key = asset.id.uuidString
            let stamp = library.artworkStamp(id: asset.id)

            if let mark = store.syncState.logos[key] {
                if stamp == mark.stamp && matches(mark, asset) { continue }
                guard admin else {
                    report("Only an admin can change a shared logo, so \(mark.name) went back to the shared version.")
                    goBack(key)
                    continue
                }
                let variantValue: Any = asset.variantLabel.isEmpty ? (NSNull() as Any) : (asset.variantLabel as Any)
                var body: [String: Any] = [
                    "name": asset.name,
                    "variant": variantValue,
                    "kind": asset.kind.rawValue,
                    "version": mark.version + 1
                ]
                if stamp != mark.stamp {
                    if stamp.isEmpty {
                        body["file_path"] = NSNull()
                    } else if let data = library.artworkData(id: asset.id) {
                        do {
                            body["file_path"] = try await uploadLogo(data, logoID: mark.serverID)
                        } catch let error as BackendError {
                            failures.append(logoProblem(error, name: asset.name))
                            continue
                        }
                    } else {
                        continue
                    }
                }
                // Only if nobody changed it since this phone last looked.
                let changed = try await patchRows(
                    "logos",
                    [idFilter(mark.serverID), URLQueryItem(name: "version", value: "eq." + String(mark.version))],
                    body)
                if changed.isEmpty {
                    report("The logo \(mark.name) was changed by someone else first, so it went back to the shared version.")
                    goBack(key)
                } else {
                    store.syncState.logos[key] = LogoMark(
                        serverID: mark.serverID, kind: asset.kind.rawValue, name: asset.name,
                        variant: asset.variantLabel, version: mark.version + 1, stamp: stamp)
                }
            } else {
                // A logo the server does not have. With no artwork of its own there is nothing to share.
                guard let data = library.artworkData(id: asset.id) else { continue }
                let serverID = asset.id.uuidString.lowercased()
                do {
                    let path = try await uploadLogo(data, logoID: serverID)
                    var row: [String: Any] = [
                        "id": serverID,
                        "business_id": Backend.businessID,
                        "kind": asset.kind.rawValue,
                        "name": asset.name,
                        "file_path": path,
                        "version": 1
                    ]
                    if !asset.variantLabel.isEmpty { row["variant"] = asset.variantLabel }
                    _ = try await call("POST", "/rest/v1/logos", json: row, prefer: "return=minimal")
                    store.syncState.logos[key] = LogoMark(
                        serverID: serverID, kind: asset.kind.rawValue, name: asset.name,
                        variant: asset.variantLabel, version: 1, stamp: stamp)
                } catch let error as BackendError {
                    if error.text.contains("duplicate key") {
                        // Someone shared the same logo a moment ago. Take theirs next round.
                        store.syncState.logoCursor = nil
                        again = true
                    } else {
                        failures.append(logoProblem(error, name: asset.name))
                    }
                }
            }
        }

        if let first = failures.first {
            report(failures.count > 1 ? first + " (and \(failures.count - 1) more)" : first)
        }
    }
}
