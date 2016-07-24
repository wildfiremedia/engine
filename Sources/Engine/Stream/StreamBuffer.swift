/**
    Buffers receive and send calls to a Stream.
 
    Receive calls are buffered by the size used to initialize
    the buffer.
 
    Send calls are buffered until `flush()` is called.
*/
public final class StreamBuffer: Stream {
    private let stream: Stream
    private let size: Int

    private var receiveIterator: IndexingIterator<[Byte]>
    internal private(set) var sendBuffer: Bytes

    public var closed: Bool {
        return stream.closed
    }

    public func setTimeout(_ timeout: Double) throws {
        try stream.setTimeout(timeout)
    }

    public func close() throws {
        try stream.close()
    }

    public init(_ stream: Stream, size: Int = 2048) {
        self.size = size
        self.stream = stream

        self.receiveIterator = Bytes().makeIterator()
        self.sendBuffer = []
    }

    public func receive() throws -> Byte? {
        guard let next = receiveIterator.next() else {
            receiveIterator = try stream.receive(max: size).makeIterator()
            return receiveIterator.next()
        }
        return next
    }

    public func receive(max: Int) throws -> Bytes {
        var bytes: Bytes = []

        for _ in 0 ..< max {
            guard let byte = try receive() else {
                break
            }

            bytes += byte
        }

        return bytes
    }

    public func send(_ bytes: Bytes) throws {
        sendBuffer += bytes
    }

    public func flush() throws {
        guard !sendBuffer.isEmpty else { return }
        try stream.send(sendBuffer)
        try stream.flush()
        sendBuffer = []
    }
}
