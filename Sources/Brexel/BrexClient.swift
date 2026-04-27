import Foundation

enum BrexAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Brex API URL could not be built."
        case .invalidResponse:
            return "Brex returned an invalid response."
        case .httpStatus(let status, _):
            if status == 401 {
                return "Brex rejected the token. Check that it is still active."
            }
            if status == 403 {
                return "Brex denied access. Check that the token can read cards, card numbers, and user limits."
            }
            return "Brex returned HTTP \(status)."
        case .decoding(let reason):
            return "Brex returned data this app could not read: \(reason)"
        case .noToken:
            return "Set a Brex API token first."
        }
    }
}

actor BrexClient {
    private let baseURL = URL(string: "https://api.brex.com")!
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func listCards(token: String) async throws -> [BrexCard] {
        guard !token.isEmpty else {
            throw BrexAPIError.noToken
        }

        var cards: [BrexCard] = []
        var cursor: String?

        repeat {
            var queryItems = [URLQueryItem(name: "limit", value: "100")]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }

            let page: CardListResponse = try await get(
                path: "/v2/cards",
                queryItems: queryItems,
                token: token
            )
            cards.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor?.isEmpty == false

        return cards
    }

    func cardPAN(cardID: String, token: String) async throws -> CardPAN {
        guard !token.isEmpty else {
            throw BrexAPIError.noToken
        }

        return try await get(
            path: "/v2/cards/\(cardID)/pan",
            queryItems: [],
            token: token
        )
    }

    func userLimit(userID: String, token: String) async throws -> UserLimit {
        guard !token.isEmpty else {
            throw BrexAPIError.noToken
        }

        return try await get(
            path: "/v2/users/\(userID)/limit",
            queryItems: [],
            token: token
        )
    }

    private func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        token: String
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BrexAPIError.invalidURL
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw BrexAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrexAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw BrexAPIError.httpStatus(httpResponse.statusCode, body)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw BrexAPIError.decoding(Self.describeDecodingError(error))
        }
    }

    private static func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            return "missing `\(key.stringValue)` at \(codingPath(context.codingPath))"
        case .typeMismatch(_, let context):
            return "unexpected value type at \(codingPath(context.codingPath))"
        case .valueNotFound(_, let context):
            return "missing value at \(codingPath(context.codingPath))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        let value = path.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "response root" : value
    }
}
