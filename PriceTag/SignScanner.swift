//
//  SignScanner.swift
//  PriceTag
//
//  Reads text from the camera or from a saved photo. Everything happens on the phone.
//

import SwiftUI
import Combine
import UIKit
import Vision
import VisionKit
import PhotosUI

// MARK: - Reading a picture

nonisolated enum TextReader {

    /// Reads every line of text in a picture. Runs off the main thread.
    static func read(_ image: UIImage) async -> [ScanItem] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: readNow(image))
            }
        }
    }

    private static func readNow(_ image: UIImage) -> [ScanItem] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Part numbers are not words; correcting them as if they were makes them worse.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(
            cgImage: cg,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )
        do { try handler.perform([request]) } catch { return [] }
        var items: [ScanItem] = []
        for observation in request.results ?? [] {
            guard let best = observation.topCandidates(1).first else { continue }
            let b = observation.boundingBox
            // Vision measures from the bottom left; the parser wants the top left.
            let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            items.append(ScanItem(text: best.string, box: box))
        }
        return items
    }
}

extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

// MARK: - Live camera

/// What the live view makes of the sign in front of the camera.
enum LiveGuess {
    /// Not enough text to say yet.
    case searching
    /// Text is being read, but no Library sign fits it.
    case unsure
    /// A Library sign that fits.
    case match(ScanMatch)

    var key: String {
        switch self {
        case .searching:    return "searching"
        case .unsure:       return "unsure"
        case .match(let m): return m.sign.id.uuidString
        }
    }
}

/// What a shot gave: the text, and the picture it was read from when there was one.
struct ScanCapture {
    var items: [ScanItem]
    var image: UIImage?
}

/// Keeps the text the live camera can see right now, guesses a match from it, and takes the shot.
@MainActor
final class LiveScanModel: NSObject, ObservableObject, DataScannerViewControllerDelegate {
    @Published var lineCount = 0
    @Published var guess: LiveGuess = .searching
    /// Set by the screen: turns the text on view into a guess. Runs about twice a second.
    var evaluate: (([ScanItem]) -> LiveGuess)?
    fileprivate weak var scanner: DataScannerViewController?
    private var items: [ScanItem] = []
    private var pending: Task<Void, Never>?
    private var lastRun = Date.distantPast
    private var lastKey = ""
    private var steady = 0

    /// The text on view right now.
    var liveItems: [ScanItem] { return items }

    /// True when this phone can scan live and the camera may be used.
    static var canScan: Bool {
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private func refresh(_ all: [RecognizedItem], in size: CGSize) {
        var next: [ScanItem] = []
        for item in all {
            guard case .text(let text) = item, size.width > 0, size.height > 0 else { continue }
            let b = item.bounds
            let xs = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x]
            let ys = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y]
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { continue }
            let box = CGRect(
                x: minX / size.width, y: minY / size.height,
                width: (maxX - minX) / size.width, height: (maxY - minY) / size.height
            )
            next.append(ScanItem(text: text.transcript, box: box))
        }
        items = next
        lineCount = next.count
        scheduleEvaluation()
    }

    /// Looks at the text on view at most twice a second, however often the camera updates.
    private func scheduleEvaluation() {
        if pending != nil { return }
        let wait = max(0.0, 0.5 - Date().timeIntervalSince(lastRun))
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            self?.runEvaluation()
        }
    }

    private func runEvaluation() {
        pending = nil
        lastRun = Date()
        guard let evaluate = evaluate else { return }
        if items.count < 4 {
            guess = .searching
            lastKey = ""
            steady = 0
            return
        }
        let next = evaluate(items)
        if next.key == lastKey {
            steady += 1
        } else {
            lastKey = next.key
            steady = 1
        }
        // A sign has to come up twice running before it shows, and "no match" three times,
        // so the card does not flicker while the phone moves.
        switch next {
        case .match:     if steady >= 2 { guess = next }
        case .unsure:    if steady >= 3 { guess = next }
        case .searching: guess = next
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        refresh(allItems, in: dataScanner.view.bounds.size)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        refresh(allItems, in: dataScanner.view.bounds.size)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        refresh(allItems, in: dataScanner.view.bounds.size)
    }

    /// Takes a full-resolution photo and reads it, which catches small print the live
    /// view skips. Falls back to what the live view could see if the photo fails.
    func capture() async -> ScanCapture {
        if let scanner = scanner, let photo = try? await scanner.capturePhoto() {
            let prepared = await SignStraightener.prepare(photo)
            return ScanCapture(items: prepared.items.isEmpty ? items : prepared.items, image: prepared.image)
        }
        return ScanCapture(items: items, image: nil)
    }
}

/// The camera view with highlight boxes over any text it can read.
struct LiveScannerView: UIViewControllerRepresentable {
    @ObservedObject var model: LiveScanModel

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = model
        model.scanner = controller
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: ()) {
        controller.stopScanning()
    }
}

// MARK: - The scan screen

/// Live camera that suggests a Library sign as it sees one, with a shutter for when it
/// finds nothing, and a way to pick a saved photo instead.
struct ScanCaptureView: View {
    @StateObject private var model = LiveScanModel()
    @State private var reading = false
    @State private var pickerItem: PhotosPickerItem?
    let onCancel: () -> Void
    let onItems: ([ScanItem], UIImage?) -> Void
    let liveGuess: ([ScanItem]) -> LiveGuess

    private var live: Bool { return LiveScanModel.canScan }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()

                if live {
                    LiveScannerView(model: model)
                        .ignoresSafeArea()
                } else {
                    unavailable
                }

                controls(wide: wide)

                if reading {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Reading the sign…")
                            .font(pt(14, .medium))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .onAppear { model.evaluate = liveGuess }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            load(item)
        }
    }

    // MARK: Controls

    /// Portrait: the shutter along the bottom. Landscape: down the right-hand edge, where
    /// a thumb rests when the phone is held sideways.
    @ViewBuilder
    private func controls(wide: Bool) -> some View {
        if wide {
            ZStack {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                }
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Spacer()
                        matchCard
                    }
                    .frame(maxWidth: 340)
                    .padding(.leading, 20)
                    .padding(.bottom, 20)
                    Spacer()
                    // The shutter sits in the middle of the edge; the photo button is placed
                    // separately so it cannot push the shutter off centre.
                    ZStack {
                        shutterButton
                        VStack(spacing: 0) {
                            Spacer()
                            photoButton
                        }
                    }
                    .padding(.trailing, 28)
                    .padding(.vertical, 24)
                }
            }
        } else {
            VStack(spacing: 0) {
                topBar
                Spacer()
                matchCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                HStack {
                    photoButton
                    Spacer()
                    shutterButton
                    Spacer()
                    Color.clear.frame(width: 52, height: 52)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(pt(15, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
            }
            Spacer()
            if live {
                Text(model.lineCount == 0 ? "Point at a sign" : "\(model.lineCount) lines read")
                    .font(pt(12, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var photoButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Image(systemName: "photo.on.rectangle")
                .font(pt(20))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private var shutterButton: some View {
        if live {
            Button(action: shoot) {
                ZStack {
                    Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(Color.white).frame(width: 60, height: 60)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// The sign the camera thinks it sees, or a hint to take a photo when nothing fits.
    @ViewBuilder
    private var matchCard: some View {
        switch model.guess {
        case .searching:
            EmptyView()
        case .match(let match):
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.strength == .strong ? "Looks like" : "Might be")
                        .font(pt(11, .semibold))
                        .foregroundColor(match.strength == .strong ? Color.green : Color.yellow)
                    Text(match.sign.name.isEmpty ? "Untitled" : match.sign.name)
                        .font(pt(16, .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(match.sign.brand + " · " + match.sign.type.title)
                        .font(pt(12))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: { onItems(model.liveItems, nil) }) {
                    Text("Open")
                        .font(pt(14, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.ptAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .unsure:
            VStack(alignment: .leading, spacing: 3) {
                Text("No match yet")
                    .font(pt(15, .bold))
                    .foregroundColor(.white)
                Text("Hold steady, or take a photo for a closer read.")
                    .font(pt(12))
                    .foregroundColor(Color.white.opacity(0.65))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.metering.unknown")
                .font(pt(34))
                .foregroundColor(Color.white.opacity(0.5))
            Text("Live scanning is not available here")
                .font(pt(16, .semibold))
                .foregroundColor(.white)
            Text("This needs a phone camera and permission to use it. You can still pick a saved photo of the sign with the button below.")
                .font(pt(13))
                .foregroundColor(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    // MARK: Actions

    private func shoot() {
        reading = true
        Task {
            let shot = await model.capture()
            reading = false
            onItems(shot.items, shot.image)
        }
    }

    private func load(_ item: PhotosPickerItem) {
        reading = true
        Task {
            var items: [ScanItem] = []
            var photo: UIImage?
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                let prepared = await SignStraightener.prepare(image)
                items = prepared.items
                photo = prepared.image
            }
            pickerItem = nil
            reading = false
            onItems(items, photo)
        }
    }
}
