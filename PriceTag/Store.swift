import SwiftUI
import Combine

/// Holds every page and saved sign, and writes them to disk.
///
/// Saves wait 0.7 seconds after the last change and run in the
/// background, so typing stays smooth.
@MainActor
final class Store: ObservableObject {

    /// The pages the user has made.
    @Published var pages: [SignPage] = [] {
        didSet { scheduleSave() }
    }

    /// Signs saved for reuse on other pages./
    @Published var library: [Sign] = [] {
        didSet { scheduleSave() }
    }

    private struct Payload: Codable, Sendable {
        var pages: [SignPage]
        var library: [Sign]
        /// Stars from before accounts; they belong to the local account.
        var favourites: [UUID]?
        var accountFavourites: [String: [UUID]]?
        var requests: [LibraryRequest]?
        var sync: SyncState?
    }

    /// The sign last copied with the copy icon, ready to paste onto any page. It
    /// lives only while the app is open.
    @Published var signClipboard: Sign?

    /// Who is using the app. Until sign-in exists this is always the local admin.
    @Published var account: Account = .local

    /// Stars, kept apart from the signs because favourites are personal: in a
    /// shared library each account has its own list.
    @Published private var favouritesByAccount: [String: Set<UUID>] = [:] {
        didSet { scheduleSave() }
    }

    /// The current account's favourites.
    var favouriteIDs: Set<UUID> {
        get { return favouritesByAccount[account.id] ?? [] }
        set { favouritesByAccount[account.id] = newValue }
    }

    /// Changes people have asked for on shared entries and not yet had decided.
    @Published var requests: [LibraryRequest] = [] {
        didSet { scheduleSave() }
    }

    /// What sync remembers between runs. Changing it never triggers another sync.
    @Published var syncState = SyncState() {
        didSet { scheduleSave(notify: false) }
    }

    /// True while this phone is signed in and keeping the Library in step online.
    @Published var isConnected = false

    /// Called after a change made here, so sync can send it.
    var onLocalChange: (() -> Void)?

    /// Whatever is keeping the Library in step online, while signed in.
    weak var remote: SyncEngine?

    private var payload: Payload {
        return Payload(
            pages: pages,
            library: library,
            favourites: nil,
            accountFavourites: favouritesByAccount.mapValues { Array($0) },
            requests: requests,
            sync: syncState
        )
    }

    private var saveTask: Task<Void, Never>?
    private var loaded = false

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("pricetag.json")
    }

    init() {
        defer { loaded = true }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            // Keep the file we could not read, so the next save cannot replace it for good.
            let keep = fileURL.deletingLastPathComponent().appendingPathComponent("pricetag-unreadable.json")
            try? data.write(to: keep, options: .atomic)
            return
        }
        pages = payload.pages
        // Earlier versions saved every copy of a sign under the same ID, which made
        // the Library draw one entry in every row. Give repeats their own ID.
        var seen = Set<UUID>()
        var repaired = false
        library = payload.library.map { entry in
            if seen.insert(entry.id).inserted { return entry }
            var copy = entry
            copy.id = UUID()
            seen.insert(copy.id)
            repaired = true
            return copy
        }
        if let saved = payload.accountFavourites {
            favouritesByAccount = saved.mapValues { Set($0) }
        } else if let old = payload.favourites {
            favouritesByAccount = [Account.local.id: Set(old)]
            repaired = true
        }
        requests = payload.requests ?? []
        syncState = payload.sync ?? SyncState()
        // Stars saved on the signs themselves by earlier versions move to the list.
        for i in library.indices where library[i].isFavourite == true {
            favouriteIDs.insert(library[i].id)
            library[i].isFavourite = nil
            repaired = true
        }
        if repaired {
            Store.write(self.payload, to: fileURL)
        }
    }

    /// Typing in any field mutates the store, and encoding the whole document on
    /// every keystroke is what made the app feel heavy. Writes are coalesced and
    /// moved off the main thread; only the last edit in a burst reaches disk.
    private func scheduleSave(notify: Bool = true) {
        guard loaded else { return }
        if notify { onLocalChange?() }
        saveTask?.cancel()
        let payload = self.payload
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            Store.write(payload, to: url)
        }
    }

    /// Call when the app leaves the foreground so a pending edit is never lost.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        let url = fileURL
        Store.write(payload, to: url)
    }

    private nonisolated static func write(_ payload: Payload, to url: URL) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Library rules
    //
    // Everything that changes a Library entry goes through these, so the rules for
    // who may change what live in one place.

    /// The entries this account can see: shared ones and its own personal copies.
    var visibleLibrary: [Sign] {
        return library.filter { LibraryRights.canSee($0, account) }
    }

    /// Saves a sign to the Library. An entry this account may change is updated;
    /// otherwise the changes become a personal copy. Returns the entry's ID.
    func save(_ sign: Sign) -> (id: UUID, result: LibrarySaveResult) {
        var entry = sign
        entry.libraryID = nil
        entry.savedAt = Date()
        entry.isFavourite = nil
        // Landscape is where a sign sits on a page, not part of the sign.
        entry.landscape = nil

        if let linked = sign.libraryID,
           let j = library.firstIndex(where: { $0.id == linked }),
           LibraryRights.canSee(library[j], account) {
            let existing = library[j]
            entry.createdBy = existing.createdBy
            entry.isPersonal = existing.isPersonal
            entry.basedOn = existing.basedOn
            if LibraryRights.canUpdateDirectly(existing, account) {
                entry.id = existing.id
                library[j] = entry
                return (existing.id, .updated)
            }
            entry.id = UUID()
            entry.createdBy = account.id
            entry.isPersonal = true
            entry.basedOn = existing.id
            library.append(entry)
            return (entry.id, .savedPersonal)
        }

        entry.id = UUID()
        entry.createdBy = account.id
        entry.isPersonal = nil
        entry.basedOn = nil
        library.append(entry)
        return (entry.id, .saved)
    }

    /// True when this account may remove the entry right now.
    func canDeleteNow(_ entry: Sign) -> Bool {
        return LibraryRights.canDeleteDirectly(entry, account)
    }

    /// Deletes the entry if this account may; otherwise asks for it to be deleted.
    func delete(_ entry: Sign) {
        if canDeleteNow(entry) {
            remove(entry.id)
        } else if !hasRequest(.delete, entry: entry.id) {
            requests.append(LibraryRequest(
                kind: .delete, entryID: entry.id,
                requestedBy: account.id, requestedByName: account.name))
        }
    }

    private func remove(_ id: UUID) {
        library.removeAll { $0.id == id }
        for key in favouritesByAccount.keys { favouritesByAccount[key]?.remove(id) }
        // Requests about an entry that is gone have nothing left to decide.
        requests.removeAll { $0.entryID == id || $0.copyID == id }
    }

    /// Asks for the shared sign behind a personal copy to take on the copy's changes.
    func requestUpdate(from copy: Sign) {
        guard let shared = copy.basedOn,
              library.contains(where: { $0.id == shared }),
              !requests.contains(where: { $0.copyID == copy.id }) else { return }
        var proposed = copy
        proposed.isPersonal = nil
        proposed.basedOn = nil
        requests.append(LibraryRequest(
            kind: .update, entryID: shared, proposed: proposed, copyID: copy.id,
            requestedBy: account.id, requestedByName: account.name))
    }

    func hasRequest(_ kind: LibraryRequest.Kind, entry id: UUID) -> Bool {
        return requests.contains { $0.kind == kind && $0.entryID == id && $0.requestedBy == account.id }
    }

    /// True when this account has already asked for the copy's changes to be shared.
    func hasUpdateRequest(copy id: UUID) -> Bool {
        return requests.contains { $0.copyID == id }
    }

    /// Requests this account is allowed to decide.
    var requestsToDecide: [LibraryRequest] {
        return requests.filter { request in
            let entry = library.first { $0.id == request.entryID }
            return entry != nil && LibraryRights.canApprove(request, entry: entry, account)
        }
    }

    func approve(_ request: LibraryRequest) {
        if account.id != Account.local.id {
            // Signed in: the server decides and applies it, then sync brings the result.
            guard let remote = remote else { return }
            Task { await remote.decide(request, approve: true) }
            return
        }
        guard let j = library.firstIndex(where: { $0.id == request.entryID }),
              LibraryRights.canApprove(request, entry: library[j], account) else { return }
        switch request.kind {
        case .delete:
            remove(request.entryID)
        case .update:
            if var proposed = request.proposed {
                let existing = library[j]
                proposed.id = existing.id
                proposed.createdBy = existing.createdBy
                proposed.isPersonal = nil
                proposed.basedOn = nil
                proposed.libraryID = nil
                proposed.savedAt = Date()
                library[j] = proposed
            }
            // The requester's personal copy has done its job.
            if let copy = request.copyID { remove(copy) }
            requests.removeAll { $0.id == request.id }
        }
    }

    func decline(_ request: LibraryRequest) {
        if account.id != Account.local.id {
            guard let remote = remote else { return }
            Task { await remote.decide(request, approve: false) }
            return
        }
        guard let entry = library.first(where: { $0.id == request.entryID }),
              LibraryRights.canApprove(request, entry: entry, account) else { return }
        requests.removeAll { $0.id == request.id }
    }

    // MARK: Signing in and out

    /// Content from before sign-in (made as the local account) now belongs to this
    /// person: an admin's becomes shared, anyone else's becomes personal copies. A backup
    /// of the Library file is kept first.
    func claimLocalContent(for newAccount: Account) {
        flush()
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("pricetag-before-sync.json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }

        claimLeftovers(for: newAccount)
        if let local = favouritesByAccount[Account.local.id] {
            favouritesByAccount[newAccount.id, default: []].formUnion(local)
            favouritesByAccount[Account.local.id] = nil
        }
        // Requests made before sign-in were only ever for trying things out.
        requests = []
        var fresh = SyncState()
        fresh.userID = newAccount.id
        syncState = fresh
    }

    /// Signs made before sign-in, or while trying out the test accounts (Sam, Alex), that
    /// nobody has claimed yet become this person's.
    func claimLeftovers(for newAccount: Account) {
        for i in library.indices where library[i].createdBy == nil
            || library[i].createdBy == Account.local.id
            || library[i].createdBy?.hasPrefix("test-") == true {
            library[i].createdBy = newAccount.id
            if !newAccount.isAdmin {
                library[i].isPersonal = true
                library[i].basedOn = nil
            }
        }
    }

    /// Stops syncing but keeps everything on the phone.
    func disconnect() {
        isConnected = false
        remote = nil
    }

    /// Takes everything that came from the shared Library off this phone and goes back to
    /// the local account. Signs made here before sign-in stay.
    func clearSharedContent() {
        // Pages are personal: once this phone has been signed in, they belong to that account.
        if syncState.userID != nil { pages = [] }
        library.removeAll { $0.createdBy != nil && $0.createdBy != Account.local.id }
        for key in favouritesByAccount.keys where key != Account.local.id {
            favouritesByAccount[key] = nil
        }
        requests = []
        syncState = SyncState()
        isConnected = false
        remote = nil
        account = .local
    }

    /// A sign was deleted by someone else: forget the stars and requests that pointed to it.
    func forgetDeleted(_ id: UUID) {
        for key in favouritesByAccount.keys { favouritesByAccount[key]?.remove(id) }
        requests.removeAll { $0.entryID == id || $0.copyID == id }
    }
}
