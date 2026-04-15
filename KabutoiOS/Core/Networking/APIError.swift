import Foundation

enum APIError: Error, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case status(code: Int, body: Data)
    case decoding(underlying: Error)
    case transport(underlying: Error)

    var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .status(let code, let body):
            let text = String(data: body, encoding: .utf8) ?? ""
            return "HTTP \(code): \(text)"
        case .decoding(let error):
            return "Decoding failed: \(error)"
        case .transport(let error):
            return "Transport error: \(error)"
        }
    }
}
