import Foundation

/// Extracts readable text from a URL.
/// Uses URLSession (native HTTP, no CORS) + simple HTML parsing.
final class URLExtractor {
    enum Error: Swift.Error, LocalizedError {
        case invalidURL
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .noContent: return "No readable content found"
            }
        }
    }

    func extract(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw Error.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw Error.noContent
        }

        return stripHTML(html)
    }

    private func stripHTML(_ html: String) -> String {
        var content = html

        // Remove script and style blocks
        content = content.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>",
                                                 with: "", options: .regularExpression)
        content = content.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>",
                                                 with: "", options: .regularExpression)

        // Remove HTML tags
        content = content.replacingOccurrences(of: "<[^>]+>", with: " ",
                                                 options: .regularExpression)

        // Decode common entities
        content = content.replacingOccurrences(of: "&amp;", with: "&")
        content = content.replacingOccurrences(of: "&lt;", with: "<")
        content = content.replacingOccurrences(of: "&gt;", with: ">")
        content = content.replacingOccurrences(of: "&quot;", with: "\"")
        content = content.replacingOccurrences(of: "&#39;", with: "'")
        content = content.replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
        content = content.replacingOccurrences(of: "\\s+", with: " ",
                                                 options: .regularExpression)

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
