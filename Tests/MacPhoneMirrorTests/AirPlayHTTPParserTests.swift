@testable import MacPhoneMirrorCore
import Foundation
import Testing

// Unit tests for incremental AirPlay HTTP/RTSP framing in AirPlayHTTPParser.

struct AirPlayHTTPParserTests {
    /// Asserts RTSP GET /info parses headers and leaves an empty buffer.
    @Test func parsesRTSPInfoWithoutBody() {
        var buffer = Data(
            """
            GET /info RTSP/1.0\r
            CSeq: 1\r
            Content-Length: 0\r
            \r

            """.utf8
        )

        let request = AirPlayHTTPParser.parseNextRequest(from: &buffer)
        #expect(request?.method == "GET")
        #expect(request?.path == "/info")
        #expect(request?.cSeq == 1)
        #expect(request?.body.isEmpty == true)
        #expect(buffer.isEmpty)
    }

    /// Asserts POST body capture and query-string stripping from the path.
    @Test func parsesPOSTWithBodyAndStripsQuery() {
        let body = Data(#"{"foo":1}"#.utf8)
        var buffer = Data(
            """
            POST /pair-setup?X-Apple-HKP=3 RTSP/1.0\r
            CSeq: 42\r
            Content-Length: \(body.count)\r
            Content-Type: application/octet-stream\r
            \r

            """.utf8
        )
        buffer.append(body)

        let request = AirPlayHTTPParser.parseNextRequest(from: &buffer)
        #expect(request?.method == "POST")
        #expect(request?.path == "/pair-setup")
        #expect(request?.cSeq == 42)
        #expect(request?.body == body)
        #expect(request?.headers["content-type"] == "application/octet-stream")
        #expect(buffer.isEmpty)
    }

    /// Asserts incomplete bodies return nil until Content-Length bytes arrive.
    @Test func waitsForCompleteBody() {
        var buffer = Data(
            """
            POST /fp-setup RTSP/1.0\r
            CSeq: 2\r
            Content-Length: 8\r
            \r
            ABCD
            """.utf8
        )

        #expect(AirPlayHTTPParser.parseNextRequest(from: &buffer) == nil)
        #expect(!buffer.isEmpty)

        buffer.append(Data("EFGH".utf8))
        let request = AirPlayHTTPParser.parseNextRequest(from: &buffer)
        #expect(request?.body == Data("ABCDEFGH".utf8))
        #expect(buffer.isEmpty)
    }

    /// Negative Content-Length is rejected without slicing the buffer.
    @Test func rejectsNegativeContentLength() {
        var buffer = Data(
            """
            POST /fp-setup RTSP/1.0\r
            CSeq: 2\r
            Content-Length: -4\r
            \r
            ABCD
            """.utf8
        )

        #expect(AirPlayHTTPParser.parseNextRequest(from: &buffer) == nil)
        #expect(buffer.isEmpty)
    }

    /// Asserts two RTSP requests are drained sequentially from one buffer.
    @Test func parsesSequentialRequestsFromSameBuffer() {
        var buffer = Data(
            """
            OPTIONS * RTSP/1.0\r
            CSeq: 1\r
            \r
            TEARDOWN rtsp://127.0.0.1/stream RTSP/1.0\r
            CSeq: 2\r
            \r

            """.utf8
        )

        let first = AirPlayHTTPParser.parseNextRequest(from: &buffer)
        let second = AirPlayHTTPParser.parseNextRequest(from: &buffer)
        #expect(first?.method == "OPTIONS")
        #expect(first?.cSeq == 1)
        #expect(second?.method == "TEARDOWN")
        #expect(second?.path == "rtsp://127.0.0.1/stream")
        #expect(second?.cSeq == 2)
        #expect(buffer.isEmpty)
    }
}
