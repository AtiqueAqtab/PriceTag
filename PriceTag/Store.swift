import SwiftUI
import Combine

@MainActor
final class Store: ObservableObject {

    @Published var pages: [SignPage] = [] {
        didSet { scheduleSave() }
    }

    @Published var library: [Sign] = [] {
        didSet { scheduleSave() }
    }

    private struct Payload: Codable, Sendable {
        var pages: [SignPage]
        var library: [Sign]
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
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        pages = payload.pages
        library = payload.library
    }

    /// Typing in any field mutates the store, and encoding the whole document on
    /// every keystroke is what made the app feel heavy. Writes are coalesced and
    /// moved off the main thread; only the last edit in a burst reaches disk.
    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        let payload = Payload(pages: pages, library: library)
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
        let payload = Payload(pages: pages, library: library)
        let url = fileURL
        Store.write(payload, to: url)
    }

    private nonisolated static func write(_ payload: Payload, to url: URL) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// A printed page always shows four signs. Short pages repeat what is there.
    func printable(_ page: SignPage) -> [Sign] {
        let signs = page.signs
        if signs.isEmpty { return [] }
        var out: [Sign] = []
        for i in 0..<4 {
            out.append(signs[i % signs.count])
        }
        return out
    }
}
