import XCTest
@testable import Engine

class HTTPBodyTests: XCTestCase {
    static var allTests = [
        ("testBufferParse", testBufferParse),
        ("testChunkedParse", testChunkedParse),
    ]

    func testBufferParse() throws {
        do {
            let expected = "hello"

            let stream = TestStream()
            try stream.send(expected)
            let body = try HTTPParser<HTTPRequest>(stream: stream).parseBody(with: ["content-length": expected.characters.count.description])

            switch body {
            case .data(let data):
                XCTAssertEqual(data.string, expected)
            default:
                XCTFail("Body not buffer")
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testChunkedParse() {
        do {
            let expected = "hello world!"

            let stream = TestStream()
            let chunkStream = ChunkStream(stream: stream)

            try chunkStream.send("hello worl")
            try chunkStream.send("d!")

            let body = try HTTPParser<HTTPRequest>(stream: stream).parseBody(with: ["transfer-encoding": "chunked"])

            switch body {
            case .data(let data):
                XCTAssertEqual(data.string, expected)
            default:
                XCTFail("Body not buffer")
            }
        } catch {
            XCTFail("\(error)")
        }
    }
}
