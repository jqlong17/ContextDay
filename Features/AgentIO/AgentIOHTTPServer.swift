import Foundation
import Network

/// Minimal local HTTP JSON server for §2.9 tools (Phase 4 light path).
/// Default bind: first free port in 18787…18797 on 127.0.0.1 only.
/// GET /health  — ContextDay-identifying JSON
/// POST /v1/tools/{name}  JSON body = arguments
/// GET  /v1/tools/{name}?k=v  (smoke convenience)
final class AgentIOHTTPServer {
    static let shared = AgentIOHTTPServer()

    static let defaultPortRange: ClosedRange<UInt16> = 18787...18797

    private var listener: NWListener?
    /// Bound port when listening; `0` if not listening.
    private(set) var port: UInt16 = 0
    private(set) var isListening = false
    private let service = AgentIOService.shared
    private let stateLock = NSLock()

    /// Bind first free port in `range` on loopback only. Never claims listening unless `.ready`.
    func start(portRange: ClosedRange<UInt16> = AgentIOHTTPServer.defaultPortRange) {
        stop()
        for candidate in portRange {
            if attemptBind(candidate) {
                return
            }
        }
        port = 0
        isListening = false
        AppLog.error(
            .agentIO,
            "failed to bind any port in \(portRange.lowerBound)-\(portRange.upperBound); not listening"
        )
    }

    /// Legacy single-port entry — scans upward within default range if preferred is busy.
    func start(port preferred: UInt16) {
        if preferred >= AgentIOHTTPServer.defaultPortRange.lowerBound,
           preferred <= AgentIOHTTPServer.defaultPortRange.upperBound {
            start(portRange: preferred...AgentIOHTTPServer.defaultPortRange.upperBound)
        } else {
            // Still try preferred first, then default range.
            if attemptBind(preferred) { return }
            start(portRange: AgentIOHTTPServer.defaultPortRange)
        }
    }

    func stop() {
        stateLock.lock()
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        isListening = false
        port = 0
        stateLock.unlock()
    }

    @discardableResult
    private func attemptBind(_ candidate: UInt16) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: candidate) else { return false }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = false
            // Localhost only — privacy: do not advertise Agent IO on LAN interfaces.
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: nwPort
            )
            let created = try NWListener(using: params)
            let sem = DispatchSemaphore(value: 0)
            var ready = false
            var failMessage: String?

            created.newConnectionHandler = { [weak self] conn in
                self?.handle(connection: conn)
            }
            created.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.stateLock.lock()
                    self.isListening = true
                    self.port = candidate
                    self.stateLock.unlock()
                    ready = true
                    sem.signal()
                case .failed(let error):
                    failMessage = error.localizedDescription
                    self.stateLock.lock()
                    self.isListening = false
                    if self.listener === created {
                        self.port = 0
                    }
                    self.stateLock.unlock()
                    sem.signal()
                case .cancelled:
                    failMessage = failMessage ?? "cancelled"
                    sem.signal()
                default:
                    break
                }
            }

            stateLock.lock()
            listener = created
            stateLock.unlock()
            created.start(queue: .global(qos: .utility))

            let waitResult = sem.wait(timeout: .now() + 0.75)
            if waitResult == .timedOut {
                AppLog.info(.agentIO, "bind \(candidate) timed out waiting for ready; cancelling")
                created.cancel()
                stateLock.lock()
                if listener === created {
                    listener = nil
                    isListening = false
                    port = 0
                }
                stateLock.unlock()
                return false
            }

            if ready {
                AppLog.info(.agentIO, "listening on 127.0.0.1:\(candidate)")
                created.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    if case .failed(let error) = state {
                        AppLog.error(.agentIO, "listener failed after ready: \(error.localizedDescription)")
                        self.stateLock.lock()
                        self.isListening = false
                        self.port = 0
                        self.stateLock.unlock()
                    }
                }
                return true
            }

            AppLog.info(.agentIO, "bind \(candidate) failed: \(failMessage ?? "unknown"); trying next")
            created.cancel()
            stateLock.lock()
            if listener === created {
                listener = nil
                isListening = false
                port = 0
            }
            stateLock.unlock()
            return false
        } catch {
            AppLog.info(.agentIO, "bind \(candidate) threw: \(error.localizedDescription); trying next")
            return false
        }
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
            stateLock.lock()
            let bound = port
            let listening = isListening
            stateLock.unlock()
            let runtime = RuntimeHealth.shared.snapshot()
            // Lean health: identity + recording flags. Full triage → tool `self_check`.
            var payload: [String: Any] = [
                "ok": listening,
                "service": "ContextDay",
                "port": Int(bound),
                "listening": listening,
                "ui_wants_recording": runtime.uiWantsRecording,
                "pipeline_running": runtime.pipelineRunning,
                "recording_desync": runtime.recordingDesync,
            ]
            payload["last_capture_error"] = runtime.lastCaptureError ?? NSNull()
            return httpJSON(200, payload)
        }

        if method == "POST", path.hasPrefix("/v1/tools/") {
            let tool = String(path.dropFirst("/v1/tools/".count)).split(separator: "?").first.map(String.init) ?? ""
            let body = raw.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
            let args = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            return dispatchTool(tool, args: args)
        }

        if method == "GET", path.hasPrefix("/v1/tools/") {
            let rest = String(path.dropFirst("/v1/tools/".count))
            let toolPart = rest.split(separator: "?", maxSplits: 1)
            let tool = String(toolPart[0])
            var args: [String: Any] = [:]
            if toolPart.count > 1 {
                for pair in toolPart[1].split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    guard kv.count == 2 else { continue }
                    let key = String(kv[0])
                    let rawVal = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    if let n = Int(rawVal) {
                        args[key] = n
                    } else if let d = Double(rawVal) {
                        args[key] = d
                    } else {
                        args[key] = rawVal
                    }
                }
            }
            return dispatchTool(tool, args: args)
        }

        return httpJSON(404, ["error": "not_found", "app": "ContextDay"])
    }

    private func dispatchTool(_ tool: String, args: [String: Any]) -> Data {
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
