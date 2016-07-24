public protocol Server: Program {
    func start(responder: HTTPResponder, errors: ServerErrorHandler) throws
}

extension Server {
    public static func start(
        host: String? = nil,
        port: Int? = nil,
        securityLayer: SecurityLayer = .none,
        responder: HTTPResponder,
        errors: ServerErrorHandler
    ) throws {
        let server = try make(host: host, port: port, securityLayer: securityLayer)
        let responder = responder
        let errors = errors
        try server.start(responder: responder, errors: errors)
    }
}
