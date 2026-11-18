import Foundation

/// What a service (Notion, Resend) answered: its status code and, for an error, its message.
struct ServiceResponse {
    let status: Int
    let message: String?
    /// The whole reply, for requests that read something back.
    var data = Data()

    var succeeded: Bool { (200..<300).contains(status) }
}

/// No connection, whichever service was being reached.
enum ServiceError: LocalizedError {
    case offline

    var errorDescription: String? {
        switch self {
        case .offline: "No internet connection. Try again when you're back online."
        }
    }
}

/// The steps every service call shares: a signed JSON request, sent, with "no connection"
/// turned into one message and the service's own error message picked out of its reply.
/// What the codes mean is up to each service.
enum ServiceRequest {
    static func post(
        _ url: URL,
        token: String,
        body: [String: Any],
        headers: [String: String] = [:],
        timeout: TimeInterval
    ) async throws -> ServiceResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request, token: token, headers: headers)
    }

    /// Reads something from the service, such as a Notion database's description.
    static func get(_ url: URL, token: String, headers: [String: String] = [:], timeout: TimeInterval) async throws -> ServiceResponse {
        try await send(URLRequest(url: url, timeoutInterval: timeout), token: token, headers: headers)
    }

    private static func send(_ request: URLRequest, token: String, headers: [String: String]) async throws -> ServiceResponse {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw ServiceError.offline
        }
        return ServiceResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: message(in: data), data: data)
    }

    /// The "message" both Notion and Resend put in an error reply, if there is one.
    static func message(in data: Data) -> String? {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
        return message?.isEmpty == false ? message : nil
    }
}
