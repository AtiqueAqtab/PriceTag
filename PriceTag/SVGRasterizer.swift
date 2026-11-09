//
//  SVGRasterizer.swift
//  PriceTag
//
//  iOS cannot decode SVG files itself, so a logo that arrives as SVG is drawn once in a
//  hidden web view and saved as an ordinary picture. Everything happens on the phone.
//

import UIKit
import WebKit

@MainActor
enum SVGRasterizer {

    /// The SVG as a picture `width` pixels wide, or nil when it cannot be drawn.
    static func image(from data: Data, width: CGFloat = 900) async -> UIImage? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              text.contains("<svg") else { return nil }
        let ratio = aspectRatio(of: text)
        let height = min(2400, max(40, (width / ratio).rounded()))
        let size = CGSize(width: width, height: height)

        let web = WKWebView(frame: CGRect(origin: .zero, size: size))
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        // Web views draw more reliably when they are on screen, so keep it there, invisible.
        web.alpha = 0.01
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        window?.insertSubview(web, at: 0)
        defer { web.removeFromSuperview() }

        let w = Int(size.width)
        let h = Int(size.height)
        let page = "<!doctype html><html><head><meta name='viewport' content='width=\(w)'>"
            + "<style>html,body{margin:0;background:transparent}img{display:block;width:\(w)px;height:\(h)px}</style>"
            + "</head><body><img src='data:image/svg+xml;base64,\(data.base64EncodedString())'></body></html>"
        let loader = PageLoader()
        web.navigationDelegate = loader
        await loader.load(page, in: web)

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: size)
        configuration.snapshotWidth = NSNumber(value: Double(width))
        guard let shot = try? await web.takeSnapshot(configuration: configuration) else { return nil }
        return hasInk(shot) ? shot : nil
    }

    /// Width over height, from the viewBox or the width and height attributes.
    private static func aspectRatio(of svg: String) -> CGFloat {
        if let g = ScanText.match("viewBox\\s*=\\s*[\"']\\s*[-0-9.]+[\\s,]+[-0-9.]+[\\s,]+([0-9.]+)[\\s,]+([0-9.]+)", in: svg),
           let w = Double(g[1]), let h = Double(g[2]), w > 0, h > 0 {
            return CGFloat(w / h)
        }
        if let w = number(after: "width", in: svg), let h = number(after: "height", in: svg), w > 0, h > 0 {
            return CGFloat(w / h)
        }
        return 1
    }

    private static func number(after attribute: String, in svg: String) -> Double? {
        guard let g = ScanText.match("<svg[^>]*\\s" + attribute + "\\s*=\\s*[\"']([0-9.]+)", in: svg) else { return nil }
        return Double(g[1])
    }

    /// False for a picture that is blank or all white, which is what a failed draw gives.
    private static func hasInk(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        if !drawn { return false }
        var i = 0
        while i < pixels.count {
            let alpha = Int(pixels[i + 3])
            let brightness = Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
            if alpha > 20 && brightness < 720 { return true }
            i += 4
        }
        return false
    }
}

/// Waits for a web view to finish loading a page, or gives up after a few seconds.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func load(_ html: String, in web: WKWebView) async {
        await withCheckedContinuation { (waiting: CheckedContinuation<Void, Never>) in
            continuation = waiting
            web.loadHTMLString(html, baseURL: nil)
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self.finish()
            }
        }
        // Give the picture a moment to decode and paint before the snapshot.
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }
}
