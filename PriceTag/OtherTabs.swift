//
//  OtherTabs.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI
import UniformTypeIdentifiers

/// Signs saved for reuse. Tap one to add it to a page.
///
/// Signs are filed in a folder for each brand. Search, filters, sorting and three
/// ways of viewing keep a big Library easy to use. The last view and sort are
/// remembered.
///
/// What this account sees and may change comes from `Store` and `LibraryRights`.
struct LibraryScreen: View {
    @EnvironmentObject var store: Store

    enum LibrarySort: String, CaseIterable, Identifiable {
        case recent, name, brand
        var id: String { return rawValue }
        var title: String {
            switch self {
            case .recent: return "Recently saved"
            case .name:   return "A–Z"
            case .brand:  return "Brand"
            }
        }
    }

    enum LibraryView: String, CaseIterable, Identifiable {
        case cards, list, grid
        var id: String { return rawValue }
        var icon: String {
            switch self {
            case .cards: return "rectangle"
            case .list:  return "list.bullet"
            case .grid:  return "square.grid.2x2"
            }
        }
    }

    @State private var query = ""
    @State private var typeFilter: SignType? = nil
    @State private var brandFilter: String? = nil
    @State private var favouritesOnly = false
    @State private var shareURL: URL?
    @State private var showImporter = false
    @State private var fileMessage: String?
    #if DEBUG
    @State private var showScanKit = false
    #endif
    @AppStorage("libraryFolders") private var showFolders = true
    @AppStorage("libraryView") private var viewRaw = LibraryView.cards.rawValue
    @AppStorage("librarySort") private var sortRaw = LibrarySort.recent.rawValue

    private var layoutMode: LibraryView { return LibraryView(rawValue: viewRaw) ?? .cards }
    private var sort: LibrarySort { return LibrarySort(rawValue: sortRaw) ?? .recent }

    // MARK: Filtering and sorting

    /// The brand folder a sign is filed in.
    private func folderName(_ sign: Sign) -> String {
        return sign.folderName
    }

    /// One folder per brand, in alphabetical order.
    private var folders: [(name: String, signs: [Sign])] {
        let groups = Dictionary(grouping: store.visibleLibrary, by: { folderName($0) })
        return groups.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { (name: $0, signs: groups[$0] ?? []) }
    }

    private func personalSuffix(_ sign: Sign) -> String {
        return sign.isPersonal == true ? " · Personal" : ""
    }

    private func searchText(_ sign: Sign) -> String {
        return sign.librarySearchText
    }

    /// The signs that pass the search and filters, in the chosen order.
    private var visible: [Sign] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matches = store.visibleLibrary.enumerated().filter { item in
            let sign = item.element
            if favouritesOnly && !store.favouriteIDs.contains(sign.id) { return false }
            if let type = typeFilter, sign.type != type { return false }
            if let brand = brandFilter, folderName(sign) != brand { return false }
            if words.isEmpty { return true }
            let text = searchText(sign)
            return words.allSatisfy { text.contains($0) }
        }
        let sorted: [(offset: Int, element: Sign)]
        switch sort {
        case .recent:
            // Saves from before dates were kept sort last, newest position first.
            sorted = matches.sorted { a, b in
                let da = a.element.savedAt ?? .distantPast
                let db = b.element.savedAt ?? .distantPast
                return da != db ? da > db : a.offset > b.offset
            }
        case .name:
            sorted = matches.sorted {
                $0.element.name.localizedCaseInsensitiveCompare($1.element.name) == .orderedAscending
            }
        case .brand:
            sorted = matches.sorted { a, b in
                let order = a.element.brand.localizedCaseInsensitiveCompare(b.element.brand)
                if order != .orderedSame { return order == .orderedAscending }
                return a.element.name.localizedCaseInsensitiveCompare(b.element.name) == .orderedAscending
            }
        }
        return sorted.map { $0.element }
    }

    private var typesPresent: [SignType] {
        return SignType.allCases.filter { type in store.visibleLibrary.contains { $0.type == type } }
    }

    private var brandsPresent: [String] {
        return Array(Set(store.visibleLibrary.map { folderName($0) })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var hasFavourites: Bool {
        return store.visibleLibrary.contains { store.favouriteIDs.contains($0.id) }
    }

    private var filtering: Bool {
        return !query.isEmpty || typeFilter != nil || brandFilter != nil || favouritesOnly
    }

    /// The folder tiles show until the person searches, filters or opens a folder.
    private var showingFolders: Bool {
        return showFolders && !filtering
    }

    private func chipName(_ type: SignType) -> String {
        switch type {
        case .regular:   return "Regular"
        case .sale:      return "Sale"
        case .clearance: return "End of season"
        case .used:      return "Parts"
        case .apparel:   return "Apparel"
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(pt(34, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                Text("Tap a sign to drop a copy onto the first page with room. Press and hold for more.")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 4)
                    .padding(.bottom, 16)

                HStack(spacing: 8) {
                    libraryFileMenu
                    AccountChip()
                        .padding(.bottom, 12)
                    Spacer(minLength: 0)
                }

                #if DEBUG
                testingMenu
                #endif

                if store.visibleLibrary.isEmpty {
                    Text("Nothing saved yet. Open a sign and tap Save to keep it here.")
                        .font(pt(14))
                        .foregroundColor(.ptDim)
                        .padding(.top, 20)
                } else {
                    requestsCard
                    searchField
                    chipRow
                    toolRow
                    if showingFolders {
                        folderGrid
                    } else {
                        folderHeader
                        results
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.ptBG)
        .sheet(item: $shareURL) { url in
            ActivityView(url: url)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], onCompletion: importLibraryFile)
        .alert("Library file", isPresented: Binding(
            get: { fileMessage != nil },
            set: { if !$0 { fileMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileMessage ?? "")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.ptDim)
            TextField("", text: $query, prompt:
                Text("Search name, brand, colour, part #").foregroundColor(Color.white.opacity(0.35))
            )
            .font(pt(14))
            .foregroundColor(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.ptDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ptInset)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(pt(12, .medium))
                .foregroundColor(on ? .white : Color.white.opacity(0.65))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(on ? Color.ptAccent : Color.ptInset)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", on: typeFilter == nil && !favouritesOnly) {
                    typeFilter = nil
                    favouritesOnly = false
                }
                if hasFavourites || favouritesOnly {
                    chip("★ Favourites", on: favouritesOnly) { favouritesOnly.toggle() }
                }
                ForEach(typesPresent) { type in
                    chip(chipName(type), on: typeFilter == type) {
                        typeFilter = typeFilter == type ? nil : type
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private var toolRow: some View {
        HStack(spacing: 6) {
            Button(action: {
                showFolders.toggle()
                brandFilter = nil
            }) {
                HStack(spacing: 5) {
                    Image(systemName: showFolders ? "folder" : "square.stack")
                    Text(showFolders ? "Folders" : "All signs")
                }
                .font(pt(12, .medium))
                .foregroundColor(Color.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ptInset)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            if !showFolders {
                Menu {
                    Button("All brands") { brandFilter = nil }
                    ForEach(brandsPresent, id: \.self) { brand in
                        Button(brand) { brandFilter = brand }
                    }
                } label: {
                    toolLabel(brandFilter ?? "Brand")
                }
            }
            Menu {
                ForEach(LibrarySort.allCases) { option in
                    Button(option.title) { sortRaw = option.rawValue }
                }
            } label: {
                toolLabel(sort.title)
            }
            Spacer()
            ForEach(LibraryView.allCases) { option in
                Button(action: { viewRaw = option.rawValue }) {
                    Image(systemName: option.icon)
                        .font(pt(14))
                        .foregroundColor(layoutMode == option ? .white : Color.white.opacity(0.4))
                        .frame(width: 32, height: 28)
                        .background(layoutMode == option ? Color.ptInset : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func toolLabel(_ title: String) -> some View {
        Text(title + " ▾")
            .font(pt(12, .medium))
            .foregroundColor(Color.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.ptInset)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Library file

    /// Export and import sit above the empty-Library message, so a phone with nothing
    /// in it can still bring a Library in.
    private var libraryFileMenu: some View {
        Menu {
            Button(action: exportLibraryFile) {
                Label("Export Library file", systemImage: "square.and.arrow.up")
            }
            Button(action: { showImporter = true }) {
                Label("Import Library file", systemImage: "square.and.arrow.down")
            }
        } label: {
            toolLabel("Library file")
        }
        .padding(.bottom, 12)
    }

    private func exportLibraryFile() {
        do {
            shareURL = try store.writeLibraryFile()
        } catch {
            fileMessage = "The Library file could not be made."
        }
    }

    private func importLibraryFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            fileMessage = "That file could not be read."
            return
        }
        do {
            fileMessage = try store.importLibrary(from: data).text
        } catch {
            fileMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// For trying out sharing before sign-in exists. Only in builds run from Xcode.
    private var testingMenu: some View {
        Menu {
            ForEach(Account.testAccounts) { account in
                Button(action: {
                    store.account = account
                    brandFilter = nil
                    favouritesOnly = false
                }) {
                    Label(account.name + (account.isAdmin ? " (admin)" : " (member)"),
                          systemImage: store.account.id == account.id ? "checkmark" : "person")
                }
                .disabled(store.isConnected)
            }
            Divider()
            Button(action: { ScanTestKit.install(into: store) }) {
                Label("Add scan test signs to Library", systemImage: "plus.circle")
            }
            Button(action: { ScanTestKit.remove(from: store) }) {
                Label("Remove scan test signs", systemImage: "minus.circle")
            }
            Button(action: { showScanKit = true }) {
                Label("Show test signs to scan", systemImage: "text.viewfinder")
            }
        } label: {
            Text("Testing as " + store.account.name + (store.account.isAdmin ? " · admin" : " · member") + " ▾")
                .font(pt(12, .medium))
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.bottom, 12)
        .sheet(isPresented: $showScanKit) { ScanTestKitView() }
    }
    #endif

    // MARK: Folders

    private var folderGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 14) {
            ForEach(folders, id: \.name) { folder in
                let newest = folder.signs.max {
                    ($0.savedAt ?? .distantPast) < ($1.savedAt ?? .distantPast)
                }
                Button(action: { brandFilter = folder.name }) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let sign = newest {
                            ScaledSign(sign: sign)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(pt(12))
                                .foregroundColor(.ptAccent)
                            Text(folder.name)
                                .font(pt(13, .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(folder.signs.count)")
                                .font(pt(12, .medium))
                                .foregroundColor(.ptDim)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Shown above the signs while a folder is open.
    @ViewBuilder
    private var folderHeader: some View {
        if showFolders, let brand = brandFilter {
            HStack(spacing: 8) {
                Button(action: { brandFilter = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Folders")
                    }
                    .font(pt(13, .medium))
                    .foregroundColor(.ptAccent)
                }
                .buttonStyle(.plain)
                Text(brand)
                    .font(pt(15, .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: Requests

    /// Changes other people have asked for that this account can approve.
    @ViewBuilder
    private var requestsCard: some View {
        let pending = store.requestsToDecide
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Overline(text: "Requests waiting")
                ForEach(pending) { request in
                    requestRow(request)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ptCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 14)
        }
    }

    private func requestRow(_ request: LibraryRequest) -> some View {
        let entry = store.library.first { $0.id == request.entryID }
        let name = (entry?.name.isEmpty ?? true) ? "Untitled" : (entry?.name ?? "Untitled")
        let verb = request.kind == .delete ? " wants to delete " : " wants to update "
        return VStack(alignment: .leading, spacing: 8) {
            if request.kind == .update, let proposed = request.proposed {
                ScaledSign(sign: proposed)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(request.requestedByName + verb + name)
                .font(pt(13, .medium))
                .foregroundColor(.white)
            HStack(spacing: 8) {
                Button(action: { store.approve(request) }) {
                    Text("Approve")
                        .font(pt(12, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.ptAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: { store.decline(request) }) {
                    Text("Decline")
                        .font(pt(12, .semibold))
                        .foregroundColor(Color.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.ptInset)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let items = visible
        if filtering {
            Text(items.count == 1 ? "1 SIGN" : "\(items.count) SIGNS")
                .font(pt(11, .medium))
                .kerning(1.1)
                .foregroundColor(Color.white.opacity(0.35))
                .padding(.bottom, 8)
        }
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No signs match.")
                    .font(pt(14))
                    .foregroundColor(.ptDim)
                Button("Clear search and filters") {
                    query = ""
                    typeFilter = nil
                    brandFilter = nil
                    favouritesOnly = false
                }
                .font(pt(13, .medium))
                .foregroundColor(.ptAccent)
            }
            .padding(.top, 12)
        } else {
            switch layoutMode {
            case .cards: cardList(items)
            case .list:  rowList(items)
            case .grid:  gridList(items)
            }
        }
    }

    private func star(_ sign: Sign, overlay: Bool) -> some View {
        let on = store.favouriteIDs.contains(sign.id)
        return Button(action: { toggleFavourite(sign) }) {
            Image(systemName: on ? "star.fill" : "star")
                .font(pt(overlay ? 13 : 15))
                .foregroundColor(on ? .yellow : Color.white.opacity(overlay ? 0.9 : 0.4))
                .padding(overlay ? 7 : 6)
                .background(overlay ? Color.black.opacity(0.45) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func menu(_ sign: Sign) -> some View {
        Group {
            Button(action: { toggleFavourite(sign) }) {
                Label(store.favouriteIDs.contains(sign.id) ? "Remove from favourites" : "Add to favourites",
                      systemImage: store.favouriteIDs.contains(sign.id) ? "star.slash" : "star")
            }
            if sign.isPersonal == true, let shared = sign.basedOn,
               store.library.contains(where: { $0.id == shared }) {
                if store.hasUpdateRequest(copy: sign.id) {
                    Button(action: {}) {
                        Label("Update requested", systemImage: "clock")
                    }
                    .disabled(true)
                } else {
                    Button(action: { store.requestUpdate(from: sign) }) {
                        Label("Ask to update the shared sign", systemImage: "arrow.up.circle")
                    }
                }
            }
            if store.canDeleteNow(sign) {
                Button(role: .destructive, action: { delete(sign) }) {
                    Label("Delete", systemImage: "trash")
                }
            } else if store.hasRequest(.delete, entry: sign.id) {
                Button(action: {}) {
                    Label("Deletion requested", systemImage: "clock")
                }
                .disabled(true)
            } else {
                Button(role: .destructive, action: { delete(sign) }) {
                    Label("Request deletion", systemImage: "trash")
                }
            }
        }
    }

    private func cardList(_ items: [Sign]) -> some View {
        LazyVStack(spacing: 14) {
            ForEach(items) { sign in
                ZStack(alignment: .topTrailing) {
                    Button(action: { add(sign) }) {
                        VStack(alignment: .leading, spacing: 8) {
                            ScaledSign(sign: sign)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(sign.name.isEmpty ? "Untitled" : sign.name)
                                .font(pt(13, .semibold))
                                .foregroundColor(.white)
                            Overline(text: sign.type.title + personalSuffix(sign))
                        }
                    }
                    .buttonStyle(.plain)
                    star(sign, overlay: true).padding(8)
                }
                .contextMenu { menu(sign) }
            }
        }
    }

    private func rowList(_ items: [Sign]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { sign in
                HStack(spacing: 10) {
                    Button(action: { add(sign) }) {
                        HStack(spacing: 12) {
                            ScaledSign(sign: sign)
                                .frame(width: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sign.name.isEmpty ? "Untitled" : sign.name)
                                    .font(pt(14, .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(sign.brand + " · " + chipName(sign.type) + personalSuffix(sign))
                                    .font(pt(11))
                                    .foregroundColor(.ptDim)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if !sign.price.isEmpty {
                                Text("$" + sign.price)
                                    .font(pt(14, .bold))
                                    .foregroundColor(Color.white.opacity(0.85))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    star(sign, overlay: false)
                }
                .padding(.vertical, 9)
                .contextMenu { menu(sign) }
                Rectangle().fill(Color.ptHair).frame(height: 1)
            }
        }
    }

    private func gridList(_ items: [Sign]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 14) {
            ForEach(items) { sign in
                ZStack(alignment: .topTrailing) {
                    Button(action: { add(sign) }) {
                        VStack(alignment: .leading, spacing: 5) {
                            ScaledSign(sign: sign)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Text(sign.name.isEmpty ? "Untitled" : sign.name)
                                .font(pt(12, .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(sign.brand + " · " + chipName(sign.type) + personalSuffix(sign))
                                .font(pt(10))
                                .foregroundColor(.ptDim)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    star(sign, overlay: true).padding(4)
                }
                .contextMenu { menu(sign) }
            }
        }
    }

    // MARK: Actions

    private func toggleFavourite(_ sign: Sign) {
        if store.favouriteIDs.contains(sign.id) {
            store.favouriteIDs.remove(sign.id)
        } else {
            store.favouriteIDs.insert(sign.id)
        }
        if !hasFavourites { favouritesOnly = false }
    }

    private func delete(_ sign: Sign) {
        store.delete(sign)
        if !hasFavourites { favouritesOnly = false }
        // Leave a folder that has just been emptied.
        if let brand = brandFilter, !store.visibleLibrary.contains(where: { folderName($0) == brand }) {
            brandFilter = nil
        }
    }

    private func add(_ sign: Sign) {
        guard let index = store.pages.firstIndex(where: { $0.signs.count < 4 }) else { return }
        store.pages[index].signs.append(sign.pageCopy())
    }
}

// Ready-made starting points for each sign type.
struct TemplatesScreen: View {
    @EnvironmentObject var store: Store

    private let presets: [(String, String, SignType)] = [
        ("Helmet — end of season", "Percent off, was price, now price, colour and size.", .clearance),
        ("Helmet — regular", "Brand, model, colour, size, single price.", .regular),
        ("Boots & apparel", "Size run with feature logos across the header.", .apparel),
        ("BMW part + fitment", "Part number, split price, model fitment list.", .used),
        ("Pre-owned unit", "Part number and FITS list under a pre-owned flag.", .used),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Templates")
                    .font(pt(34, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                Text("Starting points with the fields already laid out.")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                VStack(spacing: 12) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                        Button(action: { start(preset.2) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(preset.0)
                                        .font(pt(16, .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("USE")
                                        .font(pt(11, .medium))
                                        .kerning(0.9)
                                        .foregroundColor(.ptAccent)
                                }
                                Text(preset.1)
                                    .font(pt(13))
                                    .foregroundColor(Color.white.opacity(0.45))
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ptCard)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.ptHair, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.ptBG)
    }

    private func start(_ type: SignType) {
        if let index = store.pages.firstIndex(where: { $0.signs.count < 4 }) {
            store.pages[index].signs.append(Sign(type: type))
        } else {
            var page = SignPage()
            page.signs = [Sign(type: type)]
            store.pages.append(page)
        }
    }
}


// MARK: - Picking from the Library while building a page

extension Sign {
    /// Everything a Library search looks at, in lower case.
    var librarySearchText: String {
        let parts: [String] = [
            name, brand, variant, size, partNumber, note, condition, type.title,
            fitment.joined(separator: " "),
            featureLogos.joined(separator: " ")
        ]
        return parts.joined(separator: " ").lowercased()
    }

    /// The brand folder this sign is filed in.
    var folderName: String {
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No brand" : trimmed
    }

    /// A copy to put on a page. Saving it again updates the Library entry it came from.
    func pageCopy() -> Sign {
        var copy = self
        copy.id = UUID()
        copy.libraryID = id
        copy.savedAt = nil
        copy.isFavourite = nil
        copy.createdBy = nil
        copy.isPersonal = nil
        copy.basedOn = nil
        copy.landscape = nil
        return copy
    }
}

/// Fills empty slots on a page from the Library without leaving the page. Tap
/// signs to tick them, then add them all at once.
struct LibraryPicker: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /// How many more signs the page can take.
    let room: Int
    /// When set, only signs of this type are offered (landscape pages take Parts signs only).
    var only: SignType? = nil
    let add: ([Sign]) -> Void

    /// The Library entries this picker offers.
    private var pool: [Sign] {
        return store.visibleLibrary.filter { only == nil || $0.type == only }
    }

    private enum Mode {
        case folders, all, favourites
    }

    @State private var mode: Mode = .folders
    @State private var folder: String? = nil
    @State private var query = ""
    /// Ticked signs, in the order they were ticked.
    @State private var picked: [UUID] = []

    private var searching: Bool {
        return !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var showingFolders: Bool {
        return mode == .folders && folder == nil && !searching
    }

    private var signs: [Sign] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matches = pool.filter { sign in
            if mode == .favourites && !store.favouriteIDs.contains(sign.id) { return false }
            if let folder = folder, sign.folderName != folder { return false }
            if words.isEmpty { return true }
            let text = sign.librarySearchText
            return words.allSatisfy { text.contains($0) }
        }
        return matches.sorted {
            ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast)
        }
    }

    private var folders: [(name: String, signs: [Sign])] {
        let groups = Dictionary(grouping: pool, by: { $0.folderName })
        return groups.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { (name: $0, signs: groups[$0] ?? []) }
    }

    private var full: Bool {
        return picked.count >= room
    }

    var body: some View {
        ZStack {
            Color.ptCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        searchField
                        modeChips
                        if showingFolders {
                            folderGrid
                        } else {
                            folderHeader
                            signList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        VStack(spacing: 4) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(pt(15, .medium))
                    .foregroundColor(.ptAccent)
                Spacer()
                Text("Add from Library")
                    .font(pt(16, .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(picked.isEmpty ? "Add" : "Add \(picked.count)") { commit() }
                    .font(pt(15, .semibold))
                    .foregroundColor(picked.isEmpty ? Color.white.opacity(0.3) : .ptAccent)
                    .disabled(picked.isEmpty)
            }
            Text("\(picked.count) of \(room) picked")
                .font(pt(12))
                .foregroundColor(.ptDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.ptDim)
            TextField("", text: $query, prompt:
                Text("Search name, brand, colour, part #").foregroundColor(Color.white.opacity(0.35))
            )
            .font(pt(14))
            .foregroundColor(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.ptDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ptInset)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(pt(12, .medium))
                .foregroundColor(on ? .white : Color.white.opacity(0.65))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(on ? Color.ptAccent : Color.ptInset)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var modeChips: some View {
        HStack(spacing: 6) {
            chip("Folders", on: mode == .folders) {
                mode = .folders
                folder = nil
            }
            chip("All signs", on: mode == .all) {
                mode = .all
                folder = nil
            }
            chip("★ Favourites", on: mode == .favourites) {
                mode = .favourites
                folder = nil
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var folderGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 14) {
            ForEach(folders, id: \.name) { item in
                let newest = item.signs.max {
                    ($0.savedAt ?? .distantPast) < ($1.savedAt ?? .distantPast)
                }
                Button(action: { folder = item.name }) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let sign = newest {
                            ScaledSign(sign: sign)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(pt(12))
                                .foregroundColor(.ptAccent)
                            Text(item.name)
                                .font(pt(13, .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(item.signs.count)")
                                .font(pt(12, .medium))
                                .foregroundColor(.ptDim)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var folderHeader: some View {
        if mode == .folders, let name = folder {
            HStack(spacing: 8) {
                Button(action: { folder = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Folders")
                    }
                    .font(pt(13, .medium))
                    .foregroundColor(.ptAccent)
                }
                .buttonStyle(.plain)
                Text(name)
                    .font(pt(15, .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var signList: some View {
        let items = signs
        if items.isEmpty {
            Text("No signs match.")
                .font(pt(14))
                .foregroundColor(.ptDim)
                .padding(.top, 8)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items) { sign in
                    row(sign)
                    Rectangle().fill(Color.ptHair).frame(height: 1)
                }
            }
        }
    }

    private func row(_ sign: Sign) -> some View {
        let ticked = picked.contains(sign.id)
        let blocked = full && !ticked
        return Button(action: { toggle(sign) }) {
            HStack(spacing: 12) {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(pt(22))
                    .foregroundColor(ticked ? .ptAccent : Color.white.opacity(0.3))
                ScaledSign(sign: sign)
                    .frame(width: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sign.name.isEmpty ? "Untitled" : sign.name)
                        .font(pt(14, .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(sign.brand + " · " + sign.type.title + (sign.isPersonal == true ? " · Personal" : ""))
                        .font(pt(11))
                        .foregroundColor(.ptDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 9)
            .opacity(blocked ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
    }

    // MARK: Actions

    private func toggle(_ sign: Sign) {
        if let i = picked.firstIndex(of: sign.id) {
            picked.remove(at: i)
        } else if !full {
            picked.append(sign.id)
        }
    }

    private func commit() {
        let chosen = picked.compactMap { id in
            pool.first { $0.id == id }
        }
        add(chosen.map { $0.pageCopy() })
        dismiss()
    }
}
