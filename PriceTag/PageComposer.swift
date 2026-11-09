//
//  PageComposer.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

//
//  PageComposer.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//

import SwiftUI
import UniformTypeIdentifiers

/// Edits one page of four signs.
///
/// Tap a slot to edit its sign or change its type. The bottom bar
/// opens the print preview.
struct PageComposer: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var page: SignPage

    @State private var pickingType = false
    @State private var pickingFromLibrary = false
    /// The sign whose copy icon was last tapped on this page, for the tick.
    @State private var copiedFrom: UUID? = nil
    /// A short confirmation such as "Copied RF-1400 Helmet".
    @State private var toast: String? = nil
    /// Hides the copy icons so the signs can be seen with nothing over them.
    @State private var hideIcons = false
    @State private var editing: UUID? = nil
    @State private var pdfURL: URL? = nil
    @State private var showShare = false
    /// The sign whose options are showing.
    @State private var menuFor: UUID? = nil
    /// The sign being dragged to a new position.
    @State private var dragging: UUID? = nil
    /// True once the drag has moved over another sign. Only then does the dragged
    /// sign's slot turn into a gap, so a long press that goes nowhere hides nothing.
    @State private var dragMoved = false
    /// What to do with empty slots on a sheet that is not full; shared with the preview.
    @AppStorage("exportFill") private var fillRaw = EmptySlots.repeatToFill.rawValue
    @State private var showExportChoice = false
    @State private var choosingPages = false
    @State private var showPreview = false
    /// The scan screen is open, and the sign it asked this page to open once it closes.
    @State private var scanning = false
    @State private var scanEditID: UUID? = nil
    /// Whether the next sheet to be started is a landscape one. Only matters while the
    /// last sheet is full (or the page is empty).
    @State private var nextSheetLandscape = false

    // The body is deliberately thin — SwiftUI's type checker gives up on this view
    // if the whole page is written as one expression.
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ptBG.ignoresSafeArea()
            content
            VStack(spacing: 0) {
                clipboardBar
                bottomBar
            }
            .confirmationDialog("Export PDF", isPresented: $showExportChoice, titleVisibility: .visible) {
                Button("This page only") { exportThisPage() }
                Button("Choose more pages…") { choosingPages = true }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) { toastView }
        // A drop anywhere on the screen ends the drag.
        .onDrop(of: [.text], delegate: DragEndDelegate(dragging: $dragging, moved: $dragMoved))
        .confirmationDialog(
            "Change type, reorder or delete",
            isPresented: Binding(
                get: { menuFor != nil },
                set: { if !$0 { menuFor = nil } }
            ),
            titleVisibility: .visible,
            presenting: page.signs.first(where: { $0.id == menuFor })
        ) { sign in
            signOptions(sign)
        }
        .sheet(isPresented: $pickingType) { typeSheet }
        .sheet(isPresented: $pickingFromLibrary) { librarySheet }
        .sheet(isPresented: $choosingPages) { PagePickerSheet(selection: [page.id]) }
        .navigationDestination(isPresented: $showPreview) { PrintPreview(page: page) }
        .sheet(item: editTarget) { target in
            NavigationStack {
                SignEditor(sign: binding(for: target.id), landscape: isLandscapeSign(target.id)) { saveToLibrary(target.id) }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = pdfURL { ActivityView(url: url) }
        }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            // The editor opens only after the scan screen has gone, so two screens never fight over the page.
            if let id = scanEditID {
                scanEditID = nil
                editing = id
            }
        }) {
            ScanFlow(onPage: { sign in
                page.signs.append(sign)
                scanEditID = sign.id
            })
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                TextField("", text: $page.title, prompt:
                    Text("Untitled page").foregroundColor(Color.white.opacity(0.3))
                )
                .font(pt(28, .bold))
                .foregroundColor(.white)
                .padding(.top, 14)

                Text(summary)
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 6)


                sheetOfSigns

                Text("Tap a sign to edit · double-tap for options · drag to reorder · border is the cut line")
                    .font(pt(11))
                    .foregroundColor(Color.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, store.signClipboard == nil ? 120 : 176)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("← Pages")
                    .font(pt(15, .medium))
                    .foregroundColor(.ptAccent)
            }
            Spacer()
            Button(action: { hideIcons.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: hideIcons ? "eye" : "eye.slash")
                    Text(hideIcons ? "Show icons" : "Hide icons")
                }
                .font(pt(14, .medium))
                .foregroundColor(.ptAccent)
            }
            .buttonStyle(.plain)
            Spacer()
            NavigationLink(destination: PrintPreview(page: page)) {
                Text("Preview")
                    .font(pt(15, .medium))
                    .foregroundColor(.ptAccent)
            }
        }
        .padding(.top, 4)
    }

    /// What the header says about how full the page is.
    private var summary: String {
        let count = page.signs.count
        if count == 0 { return "Empty page · letter, 0.5in margins" }
        let sheets = page.sheetCount
        let landscape = page.sheets.filter { sheetCapacity($0) == 2 }.count
        var text = "\(count) \(count == 1 ? "sign" : "signs") · \(sheets) \(sheets == 1 ? "sheet" : "sheets")"
        if landscape > 0 { text += " (\(landscape) landscape)" }
        return text + " · letter, 0.5in margins"
    }

    /// The signs in groups, one group per printed sheet. The last group is empty when the
    /// page is empty or the sheet before it is full, so there is always somewhere to add
    /// the next sign.
    private var sheetGroups: [[Sign]] {
        var groups = page.sheets
        if let last = groups.last, last.count < sheetCapacity(last) { return groups }
        groups.append([])
        return groups
    }

    /// True when the next sign added goes on a landscape sheet: the sheet being filled is
    /// landscape, or a new sheet is about to start and landscape is chosen for it.
    private var addLandscape: Bool {
        guard let last = page.sheets.last, last.count < sheetCapacity(last) else {
            return nextSheetLandscape
        }
        return sheetCapacity(last) == 2
    }

    private func isLandscapeSign(_ id: UUID) -> Bool {
        return page.signs.first(where: { $0.id == id })?.onLandscapeSheet ?? false
    }

    private var sheetOfSigns: some View {
        let groups = sheetGroups
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.indices, id: \.self) { k in
                sheetLabel(k, groups[k])
                VStack(spacing: 7) {
                    ForEach(groups[k]) { sign in
                        signRow(sign)
                    }
                    if k == groups.count - 1 { addSlot }
                }
                .padding(7)
                .background(Color.white)
                .cornerRadius(8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: page.signs.map { $0.id })
        .padding(.top, 22)
    }

    /// The label above a sheet, with a switch between a standard sheet (four signs) and a
    /// landscape sheet (two bigger Parts signs). Landscape needs every sign on the sheet to be a Parts sign.
    private func sheetLabel(_ index: Int, _ group: [Sign]) -> some View {
        let landscape = group.isEmpty ? nextSheetLandscape : sheetCapacity(group) == 2
        let capacity = landscape ? 2 : 4
        let canLandscape = group.allSatisfy { $0.type == .used }
        return HStack(spacing: 8) {
            Overline(text: "Sheet \(index + 1)")
            Text(group.isEmpty ? "new" : "\(group.count) of \(capacity)")
                .font(pt(11))
                .foregroundColor(Color.white.opacity(0.3))
            Spacer()
            HStack(spacing: 2) {
                orientationOption("Standard", on: !landscape, enabled: true) {
                    setSheet(group, landscape: false)
                }
                orientationOption("Landscape", on: landscape, enabled: canLandscape || landscape) {
                    setSheet(group, landscape: true)
                }
            }
            .padding(2)
            .background(Color.ptInset)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 2)
        .padding(.top, index == 0 ? 0 : 14)
        .padding(.bottom, 6)
    }

    private func orientationOption(_ title: String, on: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(pt(11, on ? .semibold : .medium))
                .foregroundColor(on ? .white : Color.white.opacity(enabled ? 0.6 : 0.25))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(on ? Color.ptAccent : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Turns a sheet's signs landscape or back to standard. An empty sheet only remembers
    /// the choice for the signs added to it. A full sheet of four turned landscape becomes
    /// two landscape sheets.
    private func setSheet(_ group: [Sign], landscape: Bool) {
        if group.isEmpty {
            nextSheetLandscape = landscape
            return
        }
        let ids = Set(group.map { $0.id })
        withAnimation {
            for i in page.signs.indices where ids.contains(page.signs[i].id) {
                page.signs[i].landscape = landscape ? true : nil
            }
        }
    }

    private func signRow(_ sign: Sign) -> some View {
        let isDragging = dragging == sign.id && dragMoved
        // While it is being dragged, the sign's slot shows an empty outline that
        // travels with the drag as the other signs slide out of its way.
        return ScaledSign(sign: sign, landscape: sign.onLandscapeSheet)
            .opacity(isDragging ? 0 : 1)
            .overlay {
                if isDragging {
                    Rectangle().strokeBorder(
                        Color.black.opacity(0.25),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if !isDragging && !hideIcons {
                    cornerButtons(sign)
                }
            }
            .contentShape(Rectangle())
            // The double tap is listed first so a single tap waits to see if a second follows.
            .onTapGesture(count: 2) {
                dragging = nil
                dragMoved = false
                menuFor = sign.id
            }
            .onTapGesture {
                // A tap also clears a drag that ended without a drop, so a sign can never stay hidden.
                dragging = nil
                if dragMoved {
                    dragMoved = false
                } else {
                    editing = sign.id
                }
            }
            .accessibilityAddTraits(.isButton)
            .onDrag {
                dragging = sign.id
                dragMoved = false
                return NSItemProvider(object: sign.id.uuidString as NSString)
            } preview: {
                ScaledSign(sign: sign, landscape: sign.onLandscapeSheet)
                    .frame(width: 300, height: 300 * dragPreviewRatio(sign))
            }
            // Press and hold lifts the sign and opens the menu; moving the finger drags it instead.
            .contextMenu { signMenu(sign) }
            .onDrop(of: [.text], delegate: SignDropDelegate(target: sign.id, page: $page, dragging: $dragging, moved: $dragMoved))
    }

    /// The copy and ⋯ buttons in a sign's corner. They are not printed.
    private func cornerButtons(_ sign: Sign) -> some View {
        let copied = copiedFrom == sign.id
        return HStack(spacing: 0) {
            Button(action: { copy(sign) }) {
                cornerIcon(copied ? "checkmark" : "doc.on.doc",
                           fill: copied ? Color(hex: 0x2F9E5B) : Color.black.opacity(0.62))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy sign")
            Menu {
                signMenu(sign)
            } label: {
                cornerIcon("ellipsis", fill: Color.black.opacity(0.62))
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Sign options")
        }
    }

    private func cornerIcon(_ name: String, fill: Color) -> some View {
        return Image(systemName: name)
            .font(pt(11, .semibold))
            .foregroundColor(.white)
            .frame(width: 26, height: 26)
            .background(fill)
            .clipShape(Circle())
            .padding(4)
            .contentShape(Rectangle())
    }

    /// Everything that can be done to one sign. Shown by the ⋯ button and by pressing and holding.
    @ViewBuilder
    private func signMenu(_ sign: Sign) -> some View {
        Button(action: { copy(sign) }) {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button(action: { duplicate(sign.id) }) {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        if !sign.onLandscapeSheet {
            Menu {
                ForEach(SignType.allCases) { type in
                    Button(action: { setType(type, on: sign.id) }) {
                        if sign.type == type {
                            Label(type.title, systemImage: "checkmark")
                        } else {
                            Text(type.title)
                        }
                    }
                }
            } label: {
                Label("Change type", systemImage: "tag")
            }
        }
        if page.signs.first?.id != sign.id {
            Button(action: { move(sign.id, by: -1) }) {
                Label("Move up", systemImage: "arrow.up")
            }
        }
        if page.signs.last?.id != sign.id {
            Button(action: { move(sign.id, by: 1) }) {
                Label("Move down", systemImage: "arrow.down")
            }
        }
        Button(role: .destructive, action: { remove(sign.id) }) {
            Label("Delete sign", systemImage: "trash")
        }
    }

    /// The options for one sign, shown when it is double-tapped.
    @ViewBuilder
    private func signOptions(_ sign: Sign) -> some View {
        Button("Copy") { copy(sign) }
        Button("Duplicate") { duplicate(sign.id) }
        if !sign.onLandscapeSheet {
            ForEach(SignType.allCases) { type in
                Button(sign.type == type ? "✓ " + type.title : type.title) {
                    setType(type, on: sign.id)
                }
            }
        }
        if page.signs.first?.id != sign.id {
            Button("Move up") { move(sign.id, by: -1) }
        }
        if page.signs.last?.id != sign.id {
            Button("Move down") { move(sign.id, by: 1) }
        }
        Button("Delete sign", role: .destructive) { remove(sign.id) }
    }

    private var addSlot: some View {
        HStack(spacing: 7) {
            addSlotButton("+ New sign") { addNewSign() }
            if let copied = store.signClipboard, !addLandscape || copied.type == .used {
                let name = copied.name.isEmpty ? "sign" : copied.name
                addSlotButton("+ Paste\n" + name, highlighted: true) { paste() }
            }
        }
    }

    private func addSlotButton(_ title: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(pt(12, highlighted ? .semibold : .medium))
                .foregroundColor(highlighted ? Color.ptAccent : Color.black.opacity(0.35))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .overlay(
                    Rectangle().strokeBorder(
                        highlighted ? Color.ptAccent : Color.black.opacity(0.2),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var hasLibrarySigns: Bool {
        return store.visibleLibrary.contains { !addLandscape || $0.type == .used }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            PillButton(title: "Add sign") { addNewSign() }
            Button(action: { scanning = true }) {
                Image(systemName: "text.viewfinder")
                    .font(pt(19, .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            if hasLibrarySigns {
                PillButton(title: "Library") { pickingFromLibrary = true }
            }
            PillButton(title: "Export PDF", filled: true) {
                // With only one page there is nothing else to choose.
                if store.pages.count > 1 {
                    showExportChoice = true
                } else {
                    exportThisPage()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.ptBG.opacity(0), Color.ptBG],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    /// Shows what is on the clipboard while there is something to paste.
    @ViewBuilder
    private var clipboardBar: some View {
        if let copied = store.signClipboard {
            HStack(spacing: 6) {
                Text("Copied:")
                    .foregroundColor(Color.white.opacity(0.65))
                Text(copied.name.isEmpty ? "Untitled" : copied.name)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    store.signClipboard = nil
                    copiedFrom = nil
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .font(pt(12))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.ptInset)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let text = toast {
            Text(text)
                .font(pt(13, .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.white)
                .clipShape(Capsule())
                .padding(.bottom, store.signClipboard == nil ? 80 : 136)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private var librarySheet: some View {
        // Fills the sheet being worked on, or a new one when it is full.
        let landscape = addLandscape
        var room = landscape ? 2 : 4
        if let last = page.sheets.last, last.count < sheetCapacity(last) {
            room = sheetCapacity(last) - last.count
        }
        return LibraryPicker(room: room, only: landscape ? .used : nil) { chosen in
            for var sign in chosen {
                sign.landscape = landscape ? true : nil
                page.signs.append(sign)
            }
        }
    }

    private var typeSheet: some View {
        TypePicker { type in
            let fresh = Sign(type: type)
            page.signs.append(fresh)
            pickingType = false
            editing = fresh.id
        }
    }

    // MARK: - Sign size

    /// The aspect ratio of one sign, for the drag preview.
    private func dragPreviewRatio(_ sign: Sign) -> CGFloat {
        let height = SignFaceView.printSize.height + (sign.onLandscapeSheet ? SignFaceView.landscapeExtra : 0)
        return height / SignFaceView.printSize.width
    }

    /// A landscape sheet only holds Parts signs, so adding to one skips the type choice.
    private func addNewSign() {
        if addLandscape {
            var fresh = Sign(type: .used)
            fresh.landscape = true
            page.signs.append(fresh)
            editing = fresh.id
        } else {
            pickingType = true
        }
    }

    // MARK: - Identity, not position

    /// Signs are addressed by id everywhere. Binding the editor to an array index
    /// crashes the moment a sign is deleted or reordered while the sheet is open.
    private var editTarget: Binding<EditTarget?> {
        return Binding(
            get: {
                guard let id = editing, page.signs.contains(where: { $0.id == id }) else {
                    return nil
                }
                return EditTarget(id: id)
            },
            set: { editing = $0?.id }
        )
    }

    private func binding(for id: UUID) -> Binding<Sign> {
        return Binding(
            get: { return page.signs.first(where: { $0.id == id }) ?? Sign() },
            set: { newValue in
                if let i = page.signs.firstIndex(where: { $0.id == id }) {
                    page.signs[i] = newValue
                }
            }
        )
    }

    /// Saves the sign to the Library. The Store decides whether that updates the
    /// entry the sign came from, makes a personal copy, or adds a new entry.
    @discardableResult
    private func saveToLibrary(_ id: UUID) -> LibrarySaveResult {
        guard let i = page.signs.firstIndex(where: { $0.id == id }) else { return .saved }
        let saved = store.save(page.signs[i])
        page.signs[i].libraryID = saved.id
        return saved.result
    }

    // MARK: - Copy, paste and duplicate

    /// A page copy of a sign. It is not linked to a Library entry, so Update on the
    /// copy can never overwrite the original; Save adds it as its own entry.
    private func copyOf(_ sign: Sign) -> Sign {
        var copy = sign
        copy.id = UUID()
        copy.libraryID = nil
        return copy
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if toast == text {
                withAnimation { toast = nil }
            }
        }
    }

    /// Puts the sign on the clipboard so it can be pasted onto this or any other page.
    private func copy(_ sign: Sign) {
        store.signClipboard = sign
        copiedFrom = sign.id
        showToast("Copied " + (sign.name.isEmpty ? "sign" : sign.name))
    }

    /// Adds the copied sign to the end of the page. The clipboard keeps it, so
    /// pasting again adds another copy. Nothing opens.
    private func paste() {
        guard let copied = store.signClipboard else { return }
        var pasted = copyOf(copied)
        if addLandscape {
            if copied.type != .used {
                showToast("Landscape sheets hold Parts signs only")
                return
            }
            pasted.landscape = true
        } else {
            pasted.landscape = nil
        }
        page.signs.append(pasted)
        showToast("Pasted")
    }

    /// Adds a copy straight under the original. Nothing opens.
    private func duplicate(_ id: UUID) {
        guard let i = page.signs.firstIndex(where: { $0.id == id }) else { return }
        page.signs.insert(copyOf(page.signs[i]), at: i + 1)
    }

    /// Exports just this page, with every sheet it needs.
    private func exportThisPage() {
        // A page with several sheets goes through the preview, where sheets can be skipped.
        if page.sheetCount > 1 {
            showPreview = true
            return
        }
        let fill = EmptySlots(rawValue: fillRaw) ?? .repeatToFill
        pdfURL = exportPDF(title: page.title, sheets: printSheets([page], fill: fill))
        showShare = pdfURL != nil
    }

    private func setType(_ type: SignType, on id: UUID) {
        guard let i = page.signs.firstIndex(where: { $0.id == id }) else { return }
        page.signs[i].type = type
    }

    /// Moves a sign one place up or down. The page prints in this order.
    private func move(_ id: UUID, by step: Int) {
        guard let i = page.signs.firstIndex(where: { $0.id == id }) else { return }
        let j = i + step
        guard page.signs.indices.contains(j) else { return }
        withAnimation { page.signs.swapAt(i, j) }
    }

    private func remove(_ id: UUID) {
        if editing == id { editing = nil }
        page.signs.removeAll { $0.id == id }
    }
}

struct EditTarget: Identifiable {
    let id: UUID
}

/// Reorders the page as a dragged sign passes over the others, so the signs
/// slide out of the way while you drag.
struct SignDropDelegate: DropDelegate {
    let target: UUID
    @Binding var page: SignPage
    @Binding var dragging: UUID?
    @Binding var moved: Bool

    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != target,
              let fromIndex = page.signs.firstIndex(where: { $0.id == from }),
              let toIndex = page.signs.firstIndex(where: { $0.id == target }) else { return }
        moved = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            page.signs.move(fromOffsets: IndexSet(integer: fromIndex),
                            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        moved = false
        return true
    }
}

/// Ends a drag that is dropped outside every sign.
struct DragEndDelegate: DropDelegate {
    @Binding var dragging: UUID?
    @Binding var moved: Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        moved = false
        return true
    }
}
