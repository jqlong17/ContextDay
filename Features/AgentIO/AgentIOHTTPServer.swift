import Foundation
import Network

/// Minimal local HTTP JSON server for §2.9 tools (Phase 4 light path).
/// GET /health
/// POST /v1/tools/{name}  JSON body = arguments
final class AgentIOHTTPServer {
    static let shared = AgentIOHTTPServer()

    private var listener: NWListener?
    private(set) var port: UInt16 = 8787
    private let service = AgentIOService.shared

    func start(port: UInt16 = 8787) {
        self.port = port
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handle(connection: conn)
            }
            listener?.start(queue: .global(qos: .utility))
            NSLog("ContextDay AgentIO HTTP listening on 127.0.0.1:\(port)")
        } catch {
            NSLog("ContextDay AgentIO HTTP failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            let response = self.respond(to: data)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func respond(to requestData: Data) -> Data {
        let raw = String(data: requestData, encoding: .utf8) ?? ""
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        let requestLine = lines.first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        if method == "GET" && (path == "/health" || path == "/v1/health") {
            return httpJSON(200, ["ok": true, "service": "contextday-agentio"])
        }

        if method == "POST", path.hasPrefix("/v1/tools/") {
            let tool = String(path.dropFirst("/v1/tools/".count))
            let body = raw.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
            let args = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            do {
                let data = try AgentIOProtocol.dispatch(tool: tool, arguments: args, service: service)
                return httpRaw(200, contentType: "application/json", body: data)
            } catch let err as AgentIOError {
                let payload = try? JSONSerialization.data(withJSONObject: err.payload)
                return httpRaw(err.isUnavailable ? 501 : 400, contentType: "application/json", body: payload ?? Data("{}".utf8))
            } catch {
                return httpJSON(500, ["error": error.localizedDescription])
            }
        }

        return httpJSON(404, ["error": "not_found"])
    }

    private func httpJSON(_ status: Int, _ obj: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return httpRaw(status, contentType: "application/json", body: body)
    }

    private func httpRaw(_ status: Int, contentType: String, body: Data) -> Data {
        let reason = status == 200 ? "OK" : (status == 501 ? "Not Implemented" : "Error")
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        return out
    }
}

private extension AgentIOError {
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}
