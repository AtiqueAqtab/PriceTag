//
//  ScanFlow.swift
//  PriceTag
//
//  Scan a printed sign, find it in the Library or make a new sign from it.
//

import SwiftUI

/// The whole scan: camera, then what was found, then what to do with it.
///
/// Shown full screen from the Pages tab and from inside a page. Inside a page,
/// `onPage` receives the sign to put on that page; it is nil from the Pages tab.
struct ScanFlow: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logos = LogoLibrary.shared

    var onPage: ((Sign) -> Void)? = nil
    /// A picture to read straight away instead of opening the camera. The test signs use this.
    var picture: UIImage? = nil

    private enum Stage {
        case capture, reading, found, others, noMatch, review, done
    }

    @State private var stage: Stage
    @State private var reading = ScanReading()
    @State private var matches: [ScanMatch] = []
    @State private var chosen: ScanMatch?
    @State private var draft = Sign()
    @State private var libraryDraft: Sign?
    /// A Library sign that looks like the one being saved, and which save was asked for.
    @State private var lookAlike: (match: Sign, others: Int)?
    @State private var lookAlikeWithPage = false
    @State private var doneMessage = ""
    @State private var nothingRead = false
    @State private var choosingDestination = false
    @State private var query = ""
    @State private var tray: [ScanLeftover] = []
    @State private var brandChosen = false

    init(onPage: ((Sign) -> Void)? = nil, picture: UIImage? = nil) {
        self.onPage = onPage
        self.picture = picture
        _stage = State(initialValue: picture == nil ? .capture : .reading)
    }

    var body: some View {
        ZStack {
            Color.ptBG.ignoresSafeArea()
            switch stage {
            case .capture:
                ScanCaptureView(onCancel: { dismiss() }, onItems: { items, image in handle(items, image: image) }, liveGuess: liveGuess)
            case .reading:
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Reading the sign…")
                        .font(pt(14, .medium))
                        .foregroundColor(.white)
                }
            case .found:
                foundScreen
            case .others:
                othersScreen(noMatch: false)
            case .noMatch:
                othersScreen(noMatch: true)
            case .review:
                reviewScreen
            case .done:
                doneScreen
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Get the logo comparison ready while the camera is open.
            await LogoMatcher.warmUp()
        }
        .task {
            if let picture = picture {
                let prepared = await SignStraightener.prepare(picture)
                handle(prepared.items, image: prepared.image)
            }
        }
        .alert("No text found", isPresented: $nothingRead) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again with the whole sign in the frame and steady light.")
        }
        .confirmationDialog("Where should this sign go?", isPresented: $choosingDestination, titleVisibility: .visible) {
            if let onPage = onPage {
                Button("Add to this page") {
                    onPage(draft)
                    dismiss()
                }
            }
            Button("Add to a new page") { addToNewPage(draft) }
            Button("Save to the Library") { saveFromScan(withPage: false) }
            Button("Save to the Library and a new page") { saveFromScan(withPage: true) }
        }
        .alert(DuplicateWarning.title, isPresented: Binding(
            get: { lookAlike != nil },
            set: { if !$0 { lookAlike = nil } }
        )) {
            Button("Open it") {
                if let existing = lookAlike?.match { libraryDraft = existing.pageCopy() }
            }
            Button("Save anyway") { saveFromScan(withPage: lookAlikeWithPage, checked: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(lookAlike.map { DuplicateWarning.message($0) } ?? "")
        }
        .sheet(item: $libraryDraft) { sign in
            ScanEditHost(sign: sign)
        }
    }

    // MARK: Reading the scan

    /// What the live camera suggests while it is still looking. Cheap enough to run twice a second.
    private func liveGuess(_ items: [ScanItem]) -> LiveGuess {
        let result = ScanParser.read(items, brands: logos.names(.brand), features: logos.names(.feature))
        let ranked = ScanMatcher.rank(result, in: store.visibleLibrary, limit: 3)
        if let best = ranked.first, best.strength >= .possible { return .match(best) }
        return .unsure
    }

    /// Reads the text. When there is a photo and the brand's name was not found in the text,
    /// looks for the brand's logo in the photo too, then goes on to find a match.
    private func handle(_ items: [ScanItem], image: UIImage?) {
        let result = ScanParser.read(items, brands: logos.names(.brand), features: logos.names(.feature))
        if result.lines.isEmpty {
            nothingRead = true
            stage = .capture
            return
        }
        guard let photo = image, !result.brandFound else {
            finishReading(result)
            return
        }
        stage = .reading
        Task {
            let found = await LogoMatcher.match(photo: photo)
            var withLogo = result
            withLogo.logoCandidates = found.candidates
            withLogo.logoDebug = found.debug
            if found.confident, let top = found.candidates.first {
                withLogo.sign.brand = top.name
                withLogo.sign.brandVariant = top.variant.isEmpty ? nil : top.variant
                withLogo.brandFound = true
                withLogo.marks[.brand] = .logo
            }
            finishReading(withLogo)
        }
    }

    private func finishReading(_ result: ScanReading) {
        reading = result
        brandChosen = false
        matches = ScanMatcher.rank(result, in: store.visibleLibrary)
        query = ""
        if let best = matches.first, best.strength >= .possible {
            chosen = best
            stage = .found
        } else {
            chosen = nil
            stage = .noMatch
        }
    }

    /// Up to five other Library signs worth a look.
    private var others: [ScanMatch] {
        return Array(matches.filter { $0.id != chosen?.id }.prefix(5))
    }

    // MARK: Found in the Library

    private var foundScreen: some View {
        let match = chosen ?? matches[0]
        let changes = ScanMatcher.differences(reading, from: match.sign)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow(back: "← Scan again", backAction: { stage = .capture })

                HStack {
                    Overline(text: "Found in your Library")
                    Spacer()
                    strengthLabel(match.strength)
                }
                .padding(.top, 18)

                ScaledSign(sign: match.sign)
                    .padding(16)
                    .background(Color.ptInset)
                    .cornerRadius(12)
                    .padding(.top, 10)

                Text(match.sign.name.isEmpty ? "Untitled" : match.sign.name)
                    .font(pt(20, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 14)
                Text(match.sign.brand + " · " + match.sign.type.title + (match.sign.isPersonal == true ? " · Personal" : ""))
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 2)

                reasonChips(match.reasons)
                    .padding(.top, 12)

                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Overline(text: "What looks different")
                        ForEach(changes, id: \.self) { line in
                            Text(line)
                                .font(pt(13))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 14)
                }

                Overline(text: "What do you want to do?").padding(.top, 24).padding(.bottom, 10)
                VStack(spacing: 10) {
                    if let onPage = onPage {
                        optionRow("Edit a copy on this page",
                                  "Changes stay on this page until you update the Library.") {
                            onPage(match.sign.pageCopy())
                            dismiss()
                        }
                    }
                    optionRow("Edit the Library sign",
                              LibraryRights.canUpdateDirectly(match.sign, store.account)
                                ? "Changes update the Library for everyone."
                                : "You will get your own copy; the shared sign stays as it is.") {
                        libraryDraft = match.sign.pageCopy()
                    }
                    optionRow("Add to a new page",
                              "Starts a page with a copy of this sign.") {
                        addToNewPage(match.sign.pageCopy())
                    }
                }

                Button(action: { stage = others.isEmpty ? .noMatch : .others }) {
                    Text(others.isEmpty ? "Not this one" : "Not this one · \(others.count) other \(others.count == 1 ? "match" : "matches")")
                        .font(pt(14, .medium))
                        .foregroundColor(.ptAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: Other matches, or none

    private func othersScreen(noMatch: Bool) -> some View {
        let list = others
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow(back: noMatch ? "← Scan again" : "← Back",
                       backAction: { stage = noMatch ? .capture : .found })

                Text(noMatch ? "No close match" : "Other matches")
                    .font(pt(28, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 14)
                Text(noMatch
                     ? "Nothing in your Library looks like this sign."
                     : "Closest first. Tap one to use it instead.")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 4)

                scanSummary.padding(.top, 16)

                if !list.isEmpty {
                    Overline(text: noMatch ? "Closest in your Library" : "Other signs that could be it")
                        .padding(.top, 22).padding(.bottom, 10)
                    VStack(spacing: 10) {
                        ForEach(list) { match in
                            matchCard(match)
                        }
                    }
                }

                Overline(text: "Search the Library").padding(.top, 22).padding(.bottom, 10)
                searchBox
                let found = searchResults
                if !query.isEmpty {
                    if found.isEmpty {
                        Text("No signs match.")
                            .font(pt(13))
                            .foregroundColor(.ptDim)
                            .padding(.top, 10)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(found) { sign in
                                searchCard(sign)
                            }
                        }
                        .padding(.top, 10)
                    }
                }

                VStack(spacing: 10) {
                    PillButton(title: "Make a new sign from the scan", filled: true) { startReview() }
                    if noMatch {
                        PillButton(title: "Scan again") { stage = .capture }
                    }
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    /// What the scan read, in a few chips.
    private var scanSummary: some View {
        let sign = reading.sign
        var chips: [String] = []
        if reading.brandFound { chips.append(sign.brand) }
        if !sign.name.isEmpty { chips.append(sign.name) }
        if !sign.partNumber.isEmpty { chips.append(sign.partNumber) }
        if !sign.price.isEmpty { chips.append("$" + sign.price) }
        if !sign.size.isEmpty { chips.append(sign.size) }
        return VStack(alignment: .leading, spacing: 8) {
            Overline(text: "What the scan read")
            if chips.isEmpty {
                Text(reading.summaryText)
                    .font(pt(12))
                    .foregroundColor(Color.white.opacity(0.7))
            } else {
                WrapLayout(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(pt(12, .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func matchCard(_ match: ScanMatch) -> some View {
        return HStack(alignment: .top, spacing: 12) {
            ScaledSign(sign: match.sign)
                .frame(width: 104)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(match.sign.name.isEmpty ? "Untitled" : match.sign.name)
                        .font(pt(14, .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    strengthLabel(match.strength)
                }
                Text(match.sign.brand + " · " + shortName(match.sign.type))
                    .font(pt(11))
                    .foregroundColor(.ptDim)
                reasonChips(match.reasons)
                Button(action: { use(match) }) {
                    Text("Use this one")
                        .font(pt(12, .semibold))
                        .foregroundColor(.ptAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func searchCard(_ sign: Sign) -> some View {
        let match = ScanMatch(sign: sign, score: 0, strength: .weak, reasons: [])
        return Button(action: { use(match) }) {
            HStack(spacing: 12) {
                ScaledSign(sign: sign)
                    .frame(width: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sign.name.isEmpty ? "Untitled" : sign.name)
                        .font(pt(14, .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(sign.brand + " · " + shortName(sign.type))
                        .font(pt(11))
                        .foregroundColor(.ptDim)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.ptCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchBox: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.white.opacity(0.4))
            TextField("", text: $query, prompt: Text("Name, brand or part number").foregroundColor(Color.white.opacity(0.3)))
                .font(pt(15))
                .foregroundColor(.white)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var searchResults: [Sign] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        if terms.isEmpty { return [] }
        let hits = store.visibleLibrary.filter { sign in
            let haystack = sign.librarySearchText
            return terms.allSatisfy { haystack.contains($0) }
        }
        return Array(hits.prefix(12))
    }

    /// Picks a different Library sign as the answer.
    private func use(_ match: ScanMatch) {
        chosen = match
        stage = .found
    }

    // MARK: A new sign from the scan

    private func startReview() {
        draft = reading.sign
        tray = reading.leftovers
        stage = .review
    }

    private var reviewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow(back: "← Retake", backAction: { stage = .capture })

                VStack(alignment: .leading, spacing: 0) {
                    Overline(text: "Not in your Library")
                    Text("New sign from the scan")
                        .font(pt(26, .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)
                    Text("Look at anything marked Check, then create the sign.")
                        .font(pt(13))
                        .foregroundColor(.ptDim)
                        .padding(.top, 4)
                }
                .padding(.top, 18)

                ScaledSign(sign: draft)
                    .padding(16)
                    .background(Color.ptInset)
                    .cornerRadius(12)
                    .padding(.top, 16)

                HStack {
                    Overline(text: "Sign type")
                    Spacer()
                    MarkPill(mark: reading.mark(.type))
                }
                .padding(.top, 22).padding(.bottom, 10)
                typeChips

                fieldsBlock

                VStack(alignment: .leading, spacing: 6) {
                    Overline(text: "Text the scan read")
                    Text(reading.summaryText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.55))
                    #if DEBUG
                    if !reading.logoDebug.isEmpty {
                        Text("Logo distances: " + reading.logoDebug)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.orange.opacity(0.8))
                            .padding(.top, 6)
                    }
                    #endif
                }
                .padding(.top, 20)

                HStack(spacing: 10) {
                    PillButton(title: "Retake") { stage = .capture }
                    PillButton(title: "Cancel") { dismiss() }
                    PillButton(title: "Create sign", filled: true) { choosingDestination = true }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: Review fields

    private var fieldsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !reading.logoCandidates.isEmpty {
                logoChoices.padding(.top, 22)
            }
            Overline(text: "Fields").padding(.top, 22).padding(.bottom, 10)
            CardGroup {
                brandRow
                ReviewRow(label: "Name", text: $draft.name, placeholder: "GT-Air 3",
                          mark: reading.mark(.name))
                if draft.type == .used {
                    ReviewRow(label: "Part no.", text: $draft.partNumber, placeholder: "77411539693",
                              mark: reading.marks[.partNumber] ?? .check, mono: true)
                    PreOwnedRow(isOn: $draft.markPreOwned)
                } else {
                    ReviewRow(label: "Colour", text: $draft.variant, placeholder: "Solid matte black",
                              mark: reading.mark(.variant))
                    ReviewRow(label: "Size", text: $draft.size, placeholder: "XL",
                              mark: reading.mark(.size))
                }
                if draft.usesComparison {
                    ReviewRow(label: "Was", text: $draft.regularPrice, placeholder: "1159.95",
                              mark: reading.mark(.was), keyboard: .decimalPad)
                    ReviewRow(label: "% off", text: $draft.percentOff, placeholder: "10",
                              mark: reading.mark(.percent), keyboard: .numberPad)
                }
                ReviewRow(label: "Price", text: $draft.price, placeholder: "1043.95",
                          mark: reading.mark(.price), keyboard: .decimalPad)
                ReviewRow(label: "Note", text: $draft.note, placeholder: "Optional",
                          mark: reading.marks[.note], last: true)
            }

            if draft.type == .used && draft.fitmentRows != nil {
                Text("Fitment was read from the sign. Open the full editor after creating to adjust it.")
                    .font(pt(12))
                    .foregroundColor(.ptDim)
                    .padding(.top, 8)
            }

            if !tray.isEmpty {
                trayBlock.padding(.top, 20)
            }
        }
    }

    /// The logos that look most like the one in the photo, to tap.
    private var logoChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(text: "Logo on the sign")
            Text(reading.mark(.brand) == .logo ? "Picked from the logo. Tap another if it is wrong." : "Tap the one that matches.")
                .font(pt(12))
                .foregroundColor(.ptDim)
            HStack(spacing: 10) {
                ForEach(reading.logoCandidates) { candidate in
                    logoTile(candidate)
                }
            }
        }
    }

    private func logoTile(_ candidate: LogoCandidate) -> some View {
        let picked = draft.brand == candidate.name
        let image = LogoLibrary.shared.image(named: candidate.name, kind: .brand, variant: candidate.variant)
        return Button(action: { chooseLogo(candidate) }) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white)
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    }
                }
                .frame(height: 64)
                Text(candidate.name)
                    .font(pt(11, .medium))
                    .foregroundColor(picked ? .white : Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(picked ? Color.ptAccent.opacity(0.25) : Color.ptCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(picked ? Color.ptAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func chooseLogo(_ candidate: LogoCandidate) {
        draft.brand = candidate.name
        draft.brandVariant = candidate.variant.isEmpty ? nil : candidate.variant
        brandChosen = true
    }

    private enum Spot {
        case name, colour, size, part, note
    }

    /// Text the scan read but could not place. Each line can be sent to a field, or dropped.
    private var trayBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline(text: "Not placed yet · \(tray.count)")
            Text("The scan read these but could not tell where they go.")
                .font(pt(12))
                .foregroundColor(.ptDim)
            ForEach(tray) { item in
                HStack(spacing: 10) {
                    Text(item.text)
                        .font(pt(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button("Name") { place(item, in: .name) }
                        Button("Colour") { place(item, in: .colour) }
                        Button("Size") { place(item, in: .size) }
                        Button("Part number") { place(item, in: .part) }
                        Button("Note") { place(item, in: .note) }
                        Button("Ignore", role: .destructive) { tray.removeAll { $0.id == item.id } }
                    } label: {
                        Text("Place")
                            .font(pt(12, .semibold))
                            .foregroundColor(.ptAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.ptAccent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Color.ptCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func place(_ item: ScanLeftover, in spot: Spot) {
        switch spot {
        case .name:   draft.name = joined(draft.name, item.text)
        case .colour: draft.variant = joined(draft.variant, item.text)
        case .size:   draft.size = item.text
        case .part:   draft.partNumber = item.text
        case .note:   draft.note = joined(draft.note, item.text)
        }
        tray.removeAll { $0.id == item.id }
    }

    private func joined(_ first: String, _ second: String) -> String {
        return first.isEmpty ? second : first + " " + second
    }

    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SignType.allCases) { type in
                    let on = draft.type == type
                    Button(action: { draft.type = type }) {
                        Text(shortName(type))
                            .font(pt(13, .semibold))
                            .foregroundColor(on ? .white : Color.white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(on ? Color.ptAccent : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var brandRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Brand")
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                Picker("", selection: $draft.brand) {
                    ForEach(logos.names(.brand), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                Spacer()
                MarkPill(mark: brandChosen ? .logo : reading.mark(.brand))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: Finishing

    /// Saves the new sign to the Library, after asking if the Library already has one like it.
    private func saveFromScan(withPage: Bool, checked: Bool = false) {
        if !checked, let found = store.lookAlike(for: draft) {
            lookAlikeWithPage = withPage
            // Let the choice sheet finish closing before the warning opens.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { lookAlike = found }
            return
        }
        let saved = store.save(draft)
        if withPage {
            var copy = draft
            copy.libraryID = saved.id
            addToNewPage(copy)
        } else {
            finish("Saved to the Library.")
        }
    }

    private func addToNewPage(_ sign: Sign) {
        var page = SignPage()
        page.title = sign.name.isEmpty ? "Scanned sign" : sign.name
        page.signs = [sign]
        store.pages.append(page)
        finish("Added to a new page called “" + page.title + "”.")
    }

    private func finish(_ message: String) {
        doneMessage = message
        stage = .done
    }

    private var doneScreen: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(pt(52))
                .foregroundColor(.green)
            Text(doneMessage)
                .font(pt(16, .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            VStack(spacing: 10) {
                PillButton(title: "Scan another") { stage = .capture }
                PillButton(title: "Done", filled: true) { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: Pieces

    private func topRow(back: String, backAction: @escaping () -> Void) -> some View {
        HStack {
            Button(action: backAction) {
                Text(back)
                    .font(pt(15, .medium))
                    .foregroundColor(.ptAccent)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Text("Close")
                    .font(pt(15, .medium))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .padding(.top, 10)
    }

    private func optionRow(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(pt(15, .semibold))
                        .foregroundColor(.white)
                    Text(detail)
                        .font(pt(12))
                        .foregroundColor(.ptDim)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(pt(12, .semibold))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ptCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.ptHair, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func reasonChips(_ reasons: [ScanReason]) -> some View {
        WrapLayout(spacing: 5) {
            ForEach(reasons, id: \.self) { reason in
                HStack(spacing: 4) {
                    Image(systemName: reason.matched ? "checkmark" : "xmark")
                        .font(pt(9, .bold))
                    Text(reason.text)
                        .font(pt(11, .medium))
                }
                .foregroundColor(reason.matched ? Color.green : Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((reason.matched ? Color.green : Color.orange).opacity(0.14))
                .clipShape(Capsule())
            }
        }
    }

    private func strengthLabel(_ strength: ScanStrength) -> some View {
        let color: Color = strength == .strong ? .green : (strength == .possible ? .yellow : Color.white.opacity(0.4))
        return Text(strength.label)
            .font(pt(11, .semibold))
            .foregroundColor(color)
    }

    private func shortName(_ type: SignType) -> String {
        switch type {
        case .regular:   return "Regular"
        case .sale:      return "Sale"
        case .clearance: return "End of season"
        case .used:      return "Parts"
        case .apparel:   return "Apparel"
        }
    }
}

// MARK: - Small views

/// "Read", "Logo found", "Worked out" or "Check" beside a field.
struct MarkPill: View {
    let mark: ScanMark

    var body: some View {
        let color = tint
        return Text(mark.label)
            .font(pt(10, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var tint: Color {
        switch mark {
        case .read:   return Color.white.opacity(0.6)
        case .logo:   return Color.ptAccent
        case .worked: return Color.teal
        case .check:  return Color.orange
        }
    }
}

private struct ReviewRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var mark: ScanMark?
    var mono: Bool = false
    var keyboard: UIKeyboardType = .default
    var last: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.25)))
                    .font(mono ? Font.system(size: 15, design: .monospaced) : pt(15))
                    .foregroundColor(.white)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                if let mark = mark {
                    MarkPill(mark: mark)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if !last {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
        }
    }
}

/// The PRE-OWNED flag switch on a parts sign.
private struct PreOwnedRow: View {
    @Binding var isOn: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Pre-owned")
                    .font(pt(14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 78, alignment: .leading)
                Text("Print the PRE-OWNED flag")
                    .font(pt(15))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.ptAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }
}

/// Edits a Library sign on its own, without putting it on a page.
private struct ScanEditHost: View {
    @EnvironmentObject var store: Store
    @State var sign: Sign

    var body: some View {
        NavigationStack {
            SignEditor(sign: $sign, backTitle: "Scan") {
                let saved = store.save(sign)
                sign.libraryID = saved.id
                return saved.result
            }
        }
    }
}
