import Foundation

/// Extracts readable text from a URL.
/// Uses URLSession (native HTTP, no CORS) + simple HTML parsing.
final class URLExtractor {
    /// **刻意不是 `LocalizedError`。**
    ///
    /// 它原来是 `LocalizedError`，`errorDescription` 给的是两句**写死的英文**
    /// （`"Invalid URL"` / `"No readable content found"`）。问题不在那两句本身，在于
    /// `LocalizedError` 让 `error.localizedDescription` 变成一条**看起来可以直接上屏**
    /// 的路——分享扩展当时就是这么用的（`ShareView` 里那句 `self.error =
    /// error.localizedDescription`）。本 App 只有 6 种语言，屏上出现的那串哪一种都不是。
    ///
    /// 现在两处调用方各自映射到 `L10n` 的句子（App 内是 `url_extract_fail` 那个 alert，
    /// 扩展里同样是它），日志用 `String(describing:)`——所以这个类型不再需要、也不该有
    /// 任何面向用户的文案。**别把它加回来。**
    enum Error: Swift.Error {
        case invalidURL
        /// 响应拿到了，但按 HTTP 头声明的字符集、文档自己声明的字符集、UTF-8 都解不出文本。
        ///
        /// 它原先叫 `noContent`，而**当时唯一的抛出点就是解码失败那一步**——也就是说
        /// 「No readable content found」这句在说一件不是它的事：页面有正文，只是我们
        /// 解不开。名字和文案都会把人带偏，所以在这里分开。
        case undecodable
    }

    func extract(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw Error.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let html = Self.decode(data, response: response) else {
            throw Error.undecodable
        }

        return stripHTML(html)
    }

    // MARK: - 解码

    /// 把响应体解成字符串。
    ///
    /// **不能只试 UTF-8。** 原先这里是 `String(data: data, encoding: .utf8)`，解不出来
    /// 就抛错——而中文网页里 GBK/GB2312、日文页里 Shift_JIS、老一点的欧洲页里
    /// ISO-8859-1 仍然大量存在，它们**全都是「能读到正文、但按 UTF-8 解不开」**，
    /// 于是那些页面一律被报成「提取失败」。
    ///
    /// 顺序是**从最可信的来源往下**：HTTP 头 > 文档自己声明 > UTF-8。
    /// 两者都是页面**自称**的编码，比我们猜准得多。
    ///
    /// ⚠️ **这里没有「挨个试常见编码」那层兜底，是故意的。** `String(data:encoding:)`
    /// 对 GB18030、Latin-1 这类编码在**任意字节**上几乎都会成功，盲试等于把一张图片
    /// 或一段二进制解成一屏乱码，还照样从 `stripHTML` 里出来一段长度超过 50 的「正文」，
    /// 一路通过调用方的长度闸送进阅读页。解不出来就老实报解不出来。
    private static func decode(_ data: Data, response: URLResponse?) -> String? {
        // 1. `Content-Type: text/html; charset=gbk`
        if let header = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type"),
           let name = charsetName(in: header),
           let encoding = stringEncoding(ianaName: name),
           let text = String(data: data, encoding: encoding) {
            return text
        }

        // 2. 文档里的 `<meta charset="gbk">` 或
        //    `<meta http-equiv="Content-Type" content="text/html; charset=gbk">`
        if let name = declaredCharset(in: data),
           let encoding = stringEncoding(ianaName: name),
           let text = String(data: data, encoding: encoding) {
            return text
        }

        // 3. 没有声明、或者声明了一个我们不认识的字符集名时，UTF-8 仍是最可能的那个。
        return String(data: data, encoding: .utf8)
    }

    /// 从 `Content-Type` 那一串里抠出 `charset=` 后面那个名字。
    private static func charsetName(in contentType: String) -> String? {
        guard let range = contentType.range(of: "charset=", options: .caseInsensitive) else {
            return nil
        }
        let rest = contentType[range.upperBound...]
        let name = rest.prefix { $0 != ";" && $0 != " " }
        return name.isEmpty ? nil : String(name).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// 只看开头这几 KB。`<meta charset>` 按规范必须出现在文档很靠前的位置，
    /// 扫全文件既没必要又白费——正文页动辄几百 KB。
    private static func declaredCharset(in data: Data) -> String? {
        // `.isoLatin1` 对**任意字节**都能成功，这正是这里要的：它是「原样看一眼」，
        // 不是「认定这页是 Latin-1」。真正的解码在 `stringEncoding(ianaName:)` 那一步。
        guard let head = String(data: data.prefix(4096), encoding: .isoLatin1) else { return nil }

        let patterns = [
            "<meta[^>]+charset\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)",
            "charset\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: head,
                                               range: NSRange(head.startIndex..., in: head)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: head) else { continue }
            return String(head[range])
        }
        return nil
    }

    /// IANA 字符集名 → `String.Encoding`。
    ///
    /// 这一步非走 CoreFoundation 不可：`String.Encoding` 自己没有按名字查的入口，
    /// 而这两个函数（`CFStringConvertIANACharSetNameToEncoding` /
    /// `CFStringConvertEncodingToNSStringEncoding`）正是为这一问存在的。
    private static func stringEncoding(ianaName: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
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
