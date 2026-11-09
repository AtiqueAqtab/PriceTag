//
//  AuthStore.swift
//  PriceTag
//
//  Signing in to the shared dealership account, and whether an admin has let this person
//  in yet. This does not change what the Library shows: until the shared Library is
//  connected (a later step), the app keeps running as the local account it always has.
//

import SwiftUI
import Combine

/// Where this person stands with the dealership.
enum AccountState: Equatable {
    /// Still finding out (the app has just opened, or the server could not be reached).
    case unknown
    case signedOut
    /// Signed in, waiting for an admin to approve them.
    case pending
    case removed
    case active(Account)
}

@MainActor
final class AuthStore: ObservableObject {

    @Published private(set) var state: AccountState = .unknown
    @Published private(set) var email: String?
    @Published private(set) var busy = false
    /// The last problem, in words for the person.
    @Published var message: String?
    /// Something that is not a problem, such as "check your email".
    @Published var notice: String?

    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var userID: String?
    private var metaName: String?
    private var refreshTask: Task<Void, Error>?

    private static let refreshKey = "refresh-token"
    private static let cacheKey = "pt.cachedMembership"

    // MARK: What the phone remembers

    /// The last answer from the server, so the account screen still makes sense offline.
    private struct Remembered: Codable {
        var userID: String
        var email: String?
        var name: String
        var role: String
        var status: String
    }

    private func remember(_ item: Remembered) {
        if let data = try? JSONEncoder().encode(item) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func remembered() -> Remembered? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(Remembered.self, from: data)
    }

    private func stateFor(_ item: Remembered) -> AccountState {
        switch item.status {
        case "active":
            return .active(Account(id: item.userID, name: item.name,
                                   role: Role(rawValue: item.role) ?? .member))
        case "removed":
            return .removed
        default:
            return .pending
        }
    }

    // MARK: Starting up

    /// Called once when the app opens.
    func start() {
        guard state == .unknown else { return }
        guard Keychain.read(Self.refreshKey) != nil else {
            state = .signedOut
            return
        }
        if let item = remembered() {
            userID = item.userID
            email = item.email
            state = stateFor(item)
        }
        Task { await refresh() }
    }

    // MARK: Signing in and out

    func signIn(email: String, password: String) async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard check(address, password) else { return }
        busy = true
        defer { busy = false }
        message = nil
        notice = nil
        do {
            let data = try await BackendClient.send(
                "POST", "/auth/v1/token",
                query: [URLQueryItem(name: "grant_type", value: "password")],
                body: ["email": address, "password": password])
            try apply(data)
            await finishSignIn()
        } catch {
            show(error)
        }
    }

    func signUp(email: String, password: String, name: String) async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !person.isEmpty else {
            message = "Enter your name so the admin knows who you are."
            return
        }
        guard check(address, password) else { return }
        busy = true
        defer { busy = false }
        message = nil
        notice = nil
        do {
            let data = try await BackendClient.send(
                "POST", "/auth/v1/signup",
                body: ["email": address, "password": password, "data": ["name": person]])
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if reply?["access_token"] != nil {
                // The project is not asking for email confirmation, so this is a session already.
                try apply(data)
                await finishSignIn()
            } else {
                notice = "Account created. If we sent you an email, open its link first. Then sign in here."
            }
        } catch {
            show(error)
        }
    }

    func signOut() async {
        if let token = accessToken {
            _ = try? await BackendClient.send("POST", "/auth/v1/logout", token: token)
        }
        forgetSession()
    }

    /// Asks the server again where this person stands. Used by "Check again" and when
    /// the app comes back to the front.
    func refresh() async {
        guard Keychain.read(Self.refreshKey) != nil else { return }
        busy = true
        defer { busy = false }
        message = nil
        do {
            try await ensureFreshToken()
            try await loadMembership()
        } catch {
            show(error)
        }
    }

    // MARK: For the sync engine

    /// A request to the database as this signed-in person.
    func call(_ method: String, _ path: String, query: [URLQueryItem] = [],
              bodyData: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        try await ensureFreshToken()
        return try await BackendClient.send(
            method, path, query: query, bodyData: bodyData, headers: headers, token: accessToken)
    }

    // MARK: People (admins)

    struct Person: Identifiable, Equatable, Decodable {
        var userID: String
        var name: String
        var role: String
        var status: String
        var id: String { return userID }

        enum CodingKeys: String, CodingKey {
            case userID = "user_id", name, role, status
        }
    }

    /// Everyone who has asked to join or belongs. Only an admin gets more than their own row.
    @Published private(set) var people: [Person] = []

    var myID: String? { return userID }

    func loadPeople() async {
        do {
            try await ensureFreshToken()
            let data = try await BackendClient.send(
                "GET", "/rest/v1/members",
                query: [
                    URLQueryItem(name: "select", value: "user_id,name,role,status"),
                    URLQueryItem(name: "business_id", value: "eq." + Backend.businessID),
                    URLQueryItem(name: "order", value: "created_at.asc")
                ],
                token: accessToken)
            people = try JSONDecoder().decode([Person].self, from: data)
        } catch {
            show(error)
        }
    }

    func approve(_ person: Person) async {
        await decide("approve_member", ["p_user": person.userID, "p_business": Backend.businessID])
    }

    func remove(_ person: Person) async {
        await decide("remove_member", ["p_user": person.userID, "p_business": Backend.businessID])
    }

    func setRole(_ person: Person, to role: Role) async {
        await decide("set_member_role",
                     ["p_user": person.userID, "p_business": Backend.businessID, "p_role": role.rawValue])
    }

    /// Runs one of the admin functions on the server, which checks the caller really is an
    /// admin, then reloads the list.
    private func decide(_ function: String, _ params: [String: Any]) async {
        busy = true
        defer { busy = false }
        message = nil
        do {
            try await ensureFreshToken()
            _ = try await BackendClient.send(
                "POST", "/rest/v1/rpc/" + function, body: params, token: accessToken)
        } catch {
            show(error)
        }
        await loadPeople()
    }

    // MARK: Inside

    private func finishSignIn() async {
        do {
            try await loadMembership()
        } catch {
            // Signed in, but could not learn the status. Keep the session and let them retry.
            if state == .signedOut { state = .unknown }
            show(error)
        }
    }

    /// Finds this person's row for the dealership. If they have none, asks to join, which
    /// puts them in the waiting list until an admin approves them.
    private func loadMembership() async throws {
        guard let uid = userID else { return }
        try await ensureFreshToken()

        let data = try await BackendClient.send(
            "GET", "/rest/v1/members",
            query: [
                URLQueryItem(name: "select", value: "name,role,status"),
                URLQueryItem(name: "user_id", value: "eq." + uid),
                URLQueryItem(name: "business_id", value: "eq." + Backend.businessID)
            ],
            token: accessToken)

        struct Row: Decodable { var name: String; var role: String; var status: String }
        var rows = try JSONDecoder().decode([Row].self, from: data)

        if rows.isEmpty {
            let fallback = (email ?? "").split(separator: "@").first.map(String.init) ?? "New person"
            let wanted = (metaName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String((wanted.isEmpty ? fallback : wanted).prefix(80))
            _ = try await BackendClient.send(
                "POST", "/rest/v1/rpc/request_to_join",
                body: ["p_business": Backend.businessID, "p_name": name],
                token: accessToken)
            rows = [Row(name: name, role: "member", status: "pending")]
        }

        let row = rows[0]
        let item = Remembered(userID: uid, email: email, name: row.name, role: row.role, status: row.status)
        remember(item)
        state = stateFor(item)
    }

    // MARK: Tokens

    private struct SessionReply: Decodable {
        struct User: Decodable {
            struct Meta: Decodable { var name: String? }
            var id: String
            var email: String?
            var user_metadata: Meta?
        }
        var access_token: String
        var refresh_token: String
        var expires_in: Int?
        var user: User
    }

    /// Takes in a sign-in or refresh reply.
    private func apply(_ data: Data) throws {
        let reply = try JSONDecoder().decode(SessionReply.self, from: data)
        accessToken = reply.access_token
        accessExpiry = Date().addingTimeInterval(TimeInterval(reply.expires_in ?? 3600))
        Keychain.write(Self.refreshKey, reply.refresh_token)
        userID = reply.user.id.lowercased()
        email = reply.user.email ?? email
        metaName = reply.user.user_metadata?.name ?? metaName
    }

    /// Makes sure the access token is good for at least another minute. Two callers asking
    /// at once share one refresh, because a refresh token only works once.
    private func ensureFreshToken() async throws {
        if accessToken != nil, accessExpiry > Date().addingTimeInterval(60) { return }
        if let running = refreshTask {
            try await running.value
            return
        }
        let task = Task { try await self.refreshNow() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func refreshNow() async throws {
        guard let saved = Keychain.read(Self.refreshKey) else {
            throw BackendError(status: 401, text: "You are signed out.")
        }
        do {
            let data = try await BackendClient.send(
                "POST", "/auth/v1/token",
                query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                body: ["refresh_token": saved])
            try apply(data)
        } catch let error as BackendError where error.status == 400 || error.status == 401 {
            // The server no longer accepts this sign-in (password changed, account removed).
            forgetSession()
            throw BackendError(status: error.status, text: "Your sign-in ran out. Please sign in again.")
        }
    }

    private func forgetSession() {
        Keychain.remove(Self.refreshKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        accessToken = nil
        accessExpiry = .distantPast
        userID = nil
        metaName = nil
        email = nil
        state = .signedOut
    }

    // MARK: Wording

    private func check(_ address: String, _ password: String) -> Bool {
        if !address.contains("@") || !address.contains(".") {
            message = "Enter your email address."
            return false
        }
        if password.count < 6 {
            message = "The password needs at least 6 characters."
            return false
        }
        return true
    }

    private func show(_ error: Error) {
        if let known = error as? BackendError {
            message = known.text
        } else if error is URLError {
            message = "Can't reach the server. Check your connection."
        } else {
            message = "Something unexpected came back from the server."
        }
    }
}
