//
//  LogosScreen.swift
//  PriceTag
//
//  Created by atique aqtab on 2026-09-14.
//
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LogosScreen: View {
    @ObservedObject private var logos = LogoLibrary.shared
    @State private var kind: LogoKind = .brand
    @State private var editing: LogoAsset?
    @State private var adding = false
    @State private var newName = ""
    @State private var newVariant = ""
    @State private var report = ""

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Logos")
                    .font(pt(34, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                Text("Add artwork from Photos, Files, or the clipboard. A logo without artwork prints as a labelled box.")
                    .font(pt(13))
                    .foregroundColor(.ptDim)
                    .padding(.top, 4)
                    .padding(.bottom, 18)

                kindSwitch

                Text(kind.blurb)
                    .font(pt(12))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(logos.list(kind)) { asset in
                        Button(action: { editing = asset }) {
                            LogoCard(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: { newName = ""; newVariant = ""; adding = true }) {
                        VStack(spacing: 6) {
                            Text("+")
                                .font(pt(24, .medium))
                                .foregroundColor(.ptAccent)
                            Text(kind == .brand ? "Add brand" : "Add feature")
                                .font(pt(12, .medium))
                                .foregroundColor(.ptAccent)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 118)
                        .background(Color.ptCard.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    Color.ptAccent.opacity(0.4),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                folderReport
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.ptBG)
        .sheet(item: $editing) { asset in
            LogoDetailSheet(assetID: asset.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLogo)) { note in
            guard let id = note.object as? UUID else { return }
            editing = logos.assets.first { $0.id == id }
        }
        .alert(kind == .brand ? "New brand" : "New feature", isPresented: $adding) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.words)
            TextField("Version (optional)", text: $newVariant)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                if let asset = logos.add(name: newName, kind: kind, variant: newVariant) { editing = asset }
            }
        } message: {
            Text("Artwork can be added next.")
        }
    }

    /// What the app can actually see in the bundled Logos folder. If a file is not
    /// listed here the app never received it, which is a folder or target problem.
    private var folderReport: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FOLDER SCAN")
                    .font(pt(10, .semibold))
                    .tracking(1.2)
                    .foregroundColor(Color.white.opacity(0.35))
                Spacer()
                Button(action: { logos.syncBundledFolders(); report = LogoLibrary.scanReport() }) {
                    Text("Rescan")
                        .font(pt(11, .medium))
                        .foregroundColor(.ptAccent)
                }
                .buttonStyle(.plain)
            }
            Text(report.isEmpty ? LogoLibrary.scanReport() : report)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 24)
    }

    private var kindSwitch: some View {
        HStack(spacing: 3) {
            ForEach(LogoKind.allCases) { option in
                Button(action: { kind = option }) {
                    Text(option == .brand ? "Brands" : "Features")
                        .font(pt(13, .medium))
                        .foregroundColor(kind == option ? .white : Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(kind == option ? Color.ptAccent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct LogoCard: View {
    @ObservedObject private var logos = LogoLibrary.shared
    let asset: LogoAsset

    private var status: String {
        if asset.hasImage { return "Artwork added" }
        if logos.hasArtwork(id: asset.id) { return "Bundled with app" }
        return "No artwork"
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white)
                if let image = logos.image(id: asset.id) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    Text(asset.name.uppercased())
                        .font(pt(11, .bold))
                        .kerning(1)
                        .foregroundColor(Color.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(4)
                }
            }
            .frame(height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        Color.black.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1, dash: logos.hasArtwork(id: asset.id) ? [] : [3, 2])
                    )
            )

            Text(asset.label)
                .font(pt(12, .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(status)
                .font(pt(10))
                .foregroundColor(logos.hasArtwork(id: asset.id) ? Color.white.opacity(0.35) : .ptAccent)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.ptHair, lineWidth: 1)
        )
    }
}

struct LogoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logos = LogoLibrary.shared
    let assetID: UUID

    @State private var pick: PhotosPickerItem?
    @State private var importing = false
    @State private var name = ""
    @State private var variant = ""
    @State private var message = ""

    private var asset: LogoAsset? { return logos.assets.first { $0.id == assetID } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ptBG.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.white)
                            if let image = logos.image(id: assetID) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(14)
                            } else {
                                Text((asset?.name ?? "").uppercased())
                                    .font(pt(15, .bold))
                                    .kerning(1.4)
                                    .foregroundColor(Color.black.opacity(0.4))
                            }
                        }
                        .frame(height: 120)

                        Text("Transparent PNG works best. Wide marks are scaled to fit the sign header.")
                            .font(pt(11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .padding(.top, 8)

                        Overline(text: "Name").padding(.top, 22).padding(.bottom, 10)
                        CardGroup {
                            FieldRow(label: "Label", text: $name, placeholder: "Gore-Tex")
                            FieldRow(label: "Version", text: $variant, placeholder: "Parts · optional", last: true)
                        }

                        Text("Give a second mark for the same brand a version name — Parts, Apparel — and the sign editor offers a Logo picker.")
                            .font(pt(11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .padding(.top, 8)

                        Overline(text: "Artwork").padding(.top, 22).padding(.bottom, 10)
                        VStack(spacing: 10) {
                            PhotosPicker(selection: $pick, matching: .images) {
                                actionLabel("Choose from Photos")
                            }
                            .buttonStyle(.plain)

                            Button(action: paste) { actionLabel("Paste from clipboard") }
                                .buttonStyle(.plain)

                            Button(action: { importing = true }) { actionLabel("Import PNG from Files") }
                                .buttonStyle(.plain)

                            if asset?.hasImage == true {
                                Button(action: { logos.clearImage(for: assetID) }) {
                                    actionLabel("Remove artwork", tint: Color(red: 0.95, green: 0.4, blue: 0.4))
                                }
                                .buttonStyle(.plain)
                            } else if logos.hasArtwork(id: assetID) {
                                Text("Using artwork bundled with the app. Adding your own replaces it.")
                                    .font(pt(11))
                                    .foregroundColor(Color.white.opacity(0.3))
                                    .padding(.top, 2)
                            }
                        }

                        if !message.isEmpty {
                            Text(message)
                                .font(pt(12))
                                .foregroundColor(.ptAccent)
                                .padding(.top, 12)
                        }

                        if let current = asset {
                            Button(action: {
                                logos.rename(assetID, to: name)
                                logos.setVariant(assetID, to: variant)
                                if let made = logos.add(name: name, kind: current.kind, variant: "New version") {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        NotificationCenter.default.post(name: .openLogo, object: made.id)
                                    }
                                }
                            }) {
                                actionLabel("Add another version of " + name, tint: .ptAccent)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 18)
                        }

                        Button(action: { logos.remove(assetID); dismiss() }) {
                            Text("Delete logo")
                                .font(pt(13, .medium))
                                .foregroundColor(Color(red: 0.95, green: 0.4, blue: 0.4))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 26)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(asset?.kind == .feature ? "Feature logo" : "Brand logo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        logos.rename(assetID, to: name)
                        logos.setVariant(assetID, to: variant)
                        dismiss()
                    }
                    .tint(.ptAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            name = asset?.name ?? ""
            variant = asset?.variantLabel ?? ""
        }
        .onChange(of: pick) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    logos.setImage(data: data, for: assetID)
                    message = ""
                } else {
                    message = "That image could not be read."
                }
                pick = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .image]) { result in
            guard case let .success(url) = result else { return }
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                logos.setImage(data: data, for: assetID)
                message = ""
            } else {
                message = "That file could not be read."
            }
        }
    }

    private func paste() {
        if logos.pasteImage(for: assetID) {
            message = ""
        } else {
            message = "No image on the clipboard. Copy a logo first, then paste."
        }
    }

    private func actionLabel(_ title: String, tint: Color = .white) -> some View {
        HStack {
            Text(title)
                .font(pt(14, .medium))
                .foregroundColor(tint)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color.ptCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.ptHair, lineWidth: 1)
        )
    }
}

extension Notification.Name {
    /// Lets the detail sheet hand focus to a version it just created.
    static let openLogo = Notification.Name("openLogo")
}
