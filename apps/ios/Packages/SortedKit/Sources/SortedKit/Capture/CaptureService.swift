import Foundation

public protocol CaptureParsing: Sendable {
    func parse(_ request: ParseRequest) async throws -> ParseResponse
}

public enum CaptureError: Error, Equatable, Sendable {
    case notConfigured
    case http(status: Int)
}

/// Calls the Sorted API's parse endpoint: `POST {functionsURL}/parse`.
public struct EdgeFunctionParser: CaptureParsing {
    public var functionsURL: URL
    /// The Supabase anon key, sent as `apikey`.
    public var apiKey: String
    /// The signed-in user's access token. Until auth lands, nil sends the anon key.
    public var accessToken: @Sendable () async -> String?
    public var session: URLSession

    public init(
        functionsURL: URL, apiKey: String,
        accessToken: @escaping @Sendable () async -> String? = { nil },
        session: URLSession = .shared
    ) {
        self.functionsURL = functionsURL
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.session = session
    }

    public func parse(_ request: ParseRequest) async throws -> ParseResponse {
        var urlRequest = URLRequest(url: functionsURL.appending(path: "parse"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "apikey")
        let token = await accessToken() ?? apiKey
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder.api.encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CaptureError.http(status: status) }
        return try JSONDecoder.api.decode(ParseResponse.self, from: data)
    }
}

/// Turns a sentence into confirmation cards, and never loses what was typed.
public struct CaptureService: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The parser returned items.
        case parsed
        /// The text wasn't a request ("hello"): edit the plain task by hand.
        case noItems
        /// The parser couldn't be reached: the text comes back as a plain task.
        case failed
    }

    public struct Result: Equatable, Sendable {
        public var items: [ParsedItem]
        public var outcome: Outcome
    }

    public var parser: (any CaptureParsing)?

    public init(parser: (any CaptureParsing)?) {
        self.parser = parser
    }

    public func capture(_ request: ParseRequest) async -> Result {
        let fallback = [ParsedItem(kind: .task, title: request.text.trimmingCharacters(in: .whitespacesAndNewlines))]
        guard let parser else { return Result(items: fallback, outcome: .failed) }
        do {
            let response = try await parser.parse(request)
            return response.items.isEmpty
                ? Result(items: fallback, outcome: .noItems)
                : Result(items: response.items, outcome: .parsed)
        } catch {
            return Result(items: fallback, outcome: .failed)
        }
    }
}
