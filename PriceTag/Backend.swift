//
//  Backend.swift
//  PriceTag
//
//  Where the shared online side lives. The publishable key is meant to sit inside an app:
//  it can only do what the database's access rules (the rules in your own Supabase project) allow.
//  Never put the project's secret or service_role key here.
//

import Foundation

enum Backend {
    static let url = "https://YOUR-PROJECT.supabase.co"
    static let publishableKey = "YOUR-PUBLISHABLE-KEY"

    /// Ottawa Goodtime Centre. Set these to your own Supabase project.
    static let businessID = "00000000-0000-0000-0000-000000000000"
    static let businessName = "Ottawa Goodtime Centre"
}

/// The server said no (as opposed to the network being unreachable).
struct BackendError: LocalizedError {
    let status: Int
    let text: String
    var errorDescription: String? { return text }
}

/// A small client for the two Supabase services the app uses: sign-in (auth) and the
/// database (rest). No outside packages.
enum BackendClient {

    /// Sends one request and returns the body. Throws `BackendError` when the server
    /// answers with an error, or the system's `URLError` when it cannot be reached.
    static func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        bodyData: Data? = nil,
        headers: [String: String] = [:],
        token: String? = nil
    ) async throws -> Data {
        guard var parts = URLComponents(string: Backend.url + path) else {
            throw BackendError(status: 0, text: "The server address is wrong.")
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else {
            throw BackendError(status: 0, text: "The server address is wrong.")
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(Backend.publishableKey, forHTTPHeaderField: "apikey")
        if let token = token {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        // A body is JSON unless the caller said otherwise (a picture upload says image/png).
        if let body = body {
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if let bodyData = bodyData {
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = bodyData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw BackendError(status: status, text: friendlyMessage(status: status, data: data))
        }
        return data
    }

    // MARK: Error wording

    private struct ErrorBody: Decodable {
        var msg: String?
        var message: String?
        var error_description: String?
        var error: String?
        var error_code: String?
    }

    /// Turns the server's reply into a sentence a person can act on.
    private static func friendlyMessage(status: Int, data: Data) -> String {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let raw = body?.msg ?? body?.message ?? body?.error_description ?? body?.error ?? ""
        let code = body?.error_code ?? ""
        let lower = raw.lowercased()

        if code == "invalid_credentials" || lower.contains("invalid login credentials") {
            return "That email and password do not match."
        }
        if code == "email_not_confirmed" || lower.contains("email not confirmed") {
            return "Confirm your email first (check your inbox), then sign in."
        }
        if code == "user_already_exists" || lower.contains("already registered") {
            return "That email already has an account. Sign in instead."
        }
        if code == "weak_password" || lower.contains("password should") {
            return "Choose a longer password (at least 6 characters)."
        }
        if code == "over_email_send_rate_limit" || code == "over_request_rate_limit" || status == 429 {
            return "Too many tries just now. Wait a minute and try again."
        }
        if lower.contains("invalid email") || code == "email_address_invalid" {
            return "That email address does not look right."
        }
        if !raw.isEmpty { return raw }
        return "The server answered with an error (\(status))."
    }
}
