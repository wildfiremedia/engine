/*
    ****************************** WARNING ******************************

    (reminders)

    ******************************

    A
    server MUST reject any received request message that contains
    whitespace between a header field-name and colon with a response code
    of 400 (Bad Request).

    ******************************

    A proxy or gateway that receives an obs-fold in a response message
    that is not within a message/http container MUST either discard the
    message and replace it with a 502 (Bad Gateway) response, preferably
    with a representation explaining that unacceptable line folding was
    received, or replace each received obs-fold with one or more SP
    octets prior to interpreting the field value or forwarding the
    message downstream.

    ******************************

    The presence of a message body in a response depends on both the
    request method to which it is responding and the response status code
    (Section 3.1.2).  Responses to the HEAD request method (Section 4.3.2
    of [RFC7231]) never include a message body because the associated
    response header fields (e.g., Transfer-Encoding, Content-Length,
    etc.), if present, indicate only what their values would have been if
    the request method had been GET (Section 4.3.1 of [RFC7231]). 2xx
    (Successful) responses to a CONNECT request method (Section 4.3.6 of
    [RFC7231]) switch to tunnel mode instead of having a message body.
    All 1xx (Informational), 204 (No Content), and 304 (Not Modified)
    responses do not include a message body.  All other responses do
    include a message body, although the body might be of zero length.

    ******************************

    A server MAY send a Content-Length header field in a response to a
    HEAD request (Section 4.3.2 of [RFC7231]); a server MUST NOT send
    Content-Length in such a response unless its field-value equals the
    decimal number of octets that would have been sent in the payload
    body of a response if the same request had used the GET method.

    *****************************

    If a message is received that has multiple Content-Length header
    fields with field-values consisting of the same decimal value, or a
    single Content-Length header field with a field value containing a
    list of identical decimal values (e.g., "Content-Length: 42, 42"),
    indicating that duplicate Content-Length header fields have been
    generated or combined by an upstream message processor, then the
    recipient MUST either reject the message as invalid or replace the
    duplicated field-values with a single valid Content-Length field
    containing that decimal value prior to determining the message body
    length or forwarding the message.

    ******************************

    A recipient MUST ignore unrecognized chunk extensions.

    ******************************
*/

public enum HTTPParserError: Swift.Error {
    case streamEmpty
    case invalidStartLine
    case invalidRequest
    case invalidKeyWhitespace
    case invalidVersion
}

public final class HTTPParser<Message: HTTPMessage>: TransferParser {
    public typealias Error = HTTPParserError
    public typealias MessageType = Message

    let stream: Stream

    public init(stream: Stream) {
        self.stream = stream
    }

    public func parse() throws -> MessageType {
        let startLineComponents = try parseStartLine()
        let headers = try parseHeaders()
        let body = try parseBody(with: headers)
        return try MessageType(
            startLineComponents: startLineComponents,
            headers: headers,
            body: body
        )
    }

    /**
        https://tools.ietf.org/html/rfc2616#section-5.1

        The Request-Line begins with a method token, followed by the
        Request-URI and the protocol version, and ending with CRLF. The
        elements are separated by SP characters. No CR or LF is allowed
        except in the final CRLF sequence.

        Request-Line   = Method SP Request-URI SP HTTP-Version CRLF

        *** [WARNING] ***
        Recipients of an invalid request-line SHOULD respond with either a
        400 (Bad Request) error or a 301 (Moved Permanently) redirect with
        the request-target properly encoded.  A recipient SHOULD NOT attempt
        to autocorrect and then process the request without a redirect, since
        the invalid request-line might be deliberately crafted to bypass
        security filters along the request chain.
    */
    func parseStartLine() throws -> (method: ArraySlice<Byte>, uri: ArraySlice<Byte>, httpVersion: ArraySlice<Byte>) {
        let line = try stream.receiveLine()
        guard !line.isEmpty else { throw Error.streamEmpty }

        // Maximum 3 components(2 splits) so reason phrase can have spaces within it
        let comps = line.split(separator: .space, maxSplits: 2, omittingEmptySubsequences: true)
        guard comps.count == 3 else {
            throw Error.invalidStartLine
        }

        return (comps[0], comps[1], comps[2])
    }

    func parseHeaders() throws -> [HeaderKey: String] {
        var headers: [HeaderKey: String] = [:]

        var lastField: String? = nil

        while true {
            let line = try stream.receiveLine()
            guard !line.isEmpty else { break }

            if line[0].isWhitespace {
                guard let lastField = lastField else {
                    /*
                        https://tools.ietf.org/html/rfc7230#section-3
                        ******* [WARNING] ********
                        A sender MUST NOT send whitespace between the start-line and the
                        first header field.  A recipient that receives whitespace between the
                        start-line and the first header field MUST either reject the message
                        as invalid or consume each whitespace-preceded line without further
                        processing of it (i.e., ignore the entire line, along with any
                        subsequent lines preceded by whitespace, until a properly formed
                        header field is received or the header section is terminated).
                        The presence of such whitespace in a request might be an attempt to
                        trick a server into ignoring that field or processing the line after
                        it as a new request, either of which might result in a security
                        vulnerability if other implementations within the request chain
                        interpret the same message differently.  Likewise, the presence of
                        such whitespace in a response might be ignored by some clients or
                        cause others to cease parsing.
                    */
                    throw Error.invalidRequest
                }

                /*
                    Historically, HTTP header field values could be extended over
                    multiple lines by preceding each extra line with at least one space
                    or horizontal tab (obs-fold).  This specification deprecates such
                    line folding except within the message/http media type
                    (Section 8.3.1).  A sender MUST NOT generate a message that includes
                    line folding (i.e., that has any field-value that contains a match to
                    the obs-fold rule) unless the message is intended for packaging
                    within the message/http media type.
                    Although deprecated and we MUST NOT generate, it is POSSIBLE for older
                    systems to use this style of communication and we need to support it
                */
                let value = line
                    .trimmed([.horizontalTab, .space])
                    .string
                headers[lastField]?.append(value)
            } else {
                /*
                    Each header field consists of a case-insensitive field name followed
                    by a colon (":"), optional leading whitespace, the field value, and
                    optional trailing whitespace.
                    header-field   = field-name ":" OWS field-value OWS
                    field-name     = token
                    field-value    = *( field-content / obs-fold )
                    field-content  = field-vchar [ 1*( SP / HTAB ) field-vchar ]
                    field-vchar    = VCHAR / obs-text
                    obs-fold       = CRLF 1*( SP / HTAB )
                    ; obsolete line folding
                    ; see Section 3.2.4
                    The field-name token labels the corresponding field-value as having
                    the semantics defined by that header field.  For example, the Date
                    header field is defined in Section 7.1.1.2 of [RFC7231] as containing
                    the origination timestamp for the message in which it appears.
                */
                let comps = line.split(separator: .colon, maxSplits: 1)
                guard comps.count == 2 else { continue }

                /*
                    No whitespace is allowed between the header field-name and colon.  In
                    the past, differences in the handling of such whitespace have led to
                    security vulnerabilities in request routing and response handling.  A
                    server MUST reject any received request message that contains
                    whitespace between a header field-name and colon with a response code
                    of 400 (Bad Request).
                */
                guard comps[0].last?.isWhitespace == false else { throw Error.invalidKeyWhitespace }
                let field = comps[0].string
                let value = comps[1].array
                    .trimmed([.horizontalTab, .space])
                    .string

                headers[field] = value
                lastField = field
            }
        }

        return headers
    }

    /**
         4.3 Message Body

         The message-body (if any) of an HTTP message is used to carry the
         entity-body associated with the request or response. The message-body
         differs from the entity-body only when a transfer-coding has been
         applied, as indicated by the Transfer-Encoding header field (section
         14.41).
    */
    func parseBody(with headers: [HeaderKey: String]) throws -> HTTPBody {
        let body: Bytes

        if let contentLength = headers["content-length"].flatMap({ Int($0) }) {
            body = try stream.receive(max: contentLength)
        } else if
            let transferEncoding = headers["transfer-encoding"],
            transferEncoding.lowercased().hasSuffix("chunked") // chunked MUST be last component
        {
            /*
                3.6.1 Chunked Transfer Coding

                The chunked encoding modifies the body of a message in order to
                transfer it as a series of chunks, each with its own size indicator,
                followed by an OPTIONAL trailer containing entity-header fields. This
                allows dynamically produced content to be transferred along with the
                information necessary for the recipient to verify that it has
                received the full message.
            */
            var buffer: Bytes = []

            while true {
                let lengthData = try stream.receiveLine()

                // size must be sent
                guard lengthData.count > 0 else {
                    break
                }

                // convert hex length data to int, or end of encoding
                guard let length = lengthData.hexInt, length > 0 else {
                    break
                }


                let content = try stream.receive(max: length + Byte.crlf.count)
                buffer += content[0 ..< content.count - Byte.crlf.count]
            }

            body = buffer
        } else {
            body = []
        }
        return .data(body)
    }
}
