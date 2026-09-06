import Foundation

// Incremental HTTP/RTSP request parser for NWConnection byte streams.
// Returns nil until a full request is buffered so partial receives do not break framing.

struct AirPlayHTTPRequest: Equatable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let cSeq: Int
}

enum AirPlayHTTPParser {
    /// Parses and consumes the next complete HTTP/RTSP request from `buffer`.
    /// Returns `nil` when more bytes are needed.
    static func parseNextRequest(from buffer: inout Data) -> AirPlayHTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = buffer[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            buffer.removeAll()
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where line.contains(":") {
            let split = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if split.count == 2 {
                headers[split[0].lowercased()] = split[1]
            }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0 else {
            buffer.removeAll()
            return nil
        }
        let bodyStart = headerEnd.upperBound
        guard contentLength <= Int.max - bodyStart else {
            buffer.removeAll()
            return nil
        }
        let totalLength = bodyStart + contentLength
        guard buffer.count >= totalLength else { return nil }

        let body = Data(buffer[bodyStart ..< totalLength])
        buffer.removeSubrange(..<totalLength)

        let cSeq = Int(headers["cseq"] ?? "0") ?? 0
        let rawPath = parts[1]
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return AirPlayHTTPRequest(method: parts[0], path: path, headers: headers, body: body, cSeq: cSeq)
    }
}
