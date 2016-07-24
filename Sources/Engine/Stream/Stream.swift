public enum StreamError: Error {
    case unsupported
    case send(String, Error)
    case receive(String, Error)
    case custom(String)
}

public protocol Stream: class {
    func setTimeout(_ timeout: Double) throws

    var closed: Bool { get }
    func close() throws

    func send(_ bytes: Bytes) throws
    func flush() throws

    func receive(max: Int) throws -> Bytes

    // Optional, performance
    func receive() throws -> Byte?
}

extension Stream {
	/**
        Reads and filters non-valid ASCII characters
        from the stream until a new line character is returned.
    */
    public func receiveLine() throws -> Bytes {
        var line: Bytes = []

        var lastByte: Byte? = nil

        while let byte = try receive() {
            // Continues until a `crlf` sequence is found
            if byte == .newLine && lastByte == .carriageReturn {
                break
            }

            // Skip over any non-valid ASCII characters
            if byte > .carriageReturn {
                line += byte
            }

            lastByte = byte
        }

        return line
    }

    /**
        Sometimes we let sockets queue things up before flushing, but in situations like web sockets,
        we may want to skip that functionality
    */
    public func send(_ bytes: Bytes, flushing: Bool) throws {
        try send(bytes)
        if flushing { try flush() }
    }

    /**
        Default implementation of receive grabs a one
        byte array from the stream and returns the first.
     
        This can be overridden with something more performant.
    */
    public func receive() throws -> Byte? {
        return try receive(max: 1).first
    }
}

extension Stream {
    public func send(_ byte: Byte) throws {
        try send([byte])
    }

    public func send(_ string: String) throws {
        try send(string.bytes)
    }
}

extension Stream {
    public func sendLine() throws {
        try send([.carriageReturn, .newLine])
    }
}
