import Foundation

/// Phase 4 MCP transport over stdio (JSON-RPC 2.0 + Content-Length framing).
/// No third-party MCP SDK — tools call `AgentIOProtocol.dispatch` unchanged.
/// Launch: `ContextDay.app/Contents/MacOS/ContextDay --mcp`
enum AgentIOMCPStdio {
    private static let protocolVersion = "2024-11-05"

    /// Blocks on stdin until EOF. Does not start AppKit UI.
    static func run(service: AgentIOService = .shared) {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        while true {
            guard let message = readMessage(from: stdin) else { break }
            if let response = handle(message: message, service: service) {
                writeMessage(response, to: stdout)
            }
        }
    }

    // MARK: - Framing (LSP / MCP Content-Length)

    private static func readMessage(from handle: FileHandle) -> [String: Any]? {
        var header = Data()
        while true {
            guard let b = try? handle.read(upToCount: 1), !b.isEmpty else { return nil }
            header.append(b)
            if header.count >= 4, header.suffix(4) == Data([13, 10, 13, 10]) { // \r\n\r\n
                break
            }
            // Also accept \n\n for friendlier local testing.
            if header.count >= 2, header.suffix(2) == Data([10, 10]) {
                break
            }
            if header.count > 65_536 { return nil }
        }
        let headerText = String(data: header, encoding: .utf8) ?? ""
        var length = 0
        for line in headerText.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        guard length > 0, let body = try? handle.read(upToCount: length), body.count == length else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private static func writeMessage(_ object: [String: Any], to handle: FileHandle) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
        let header = "Content-Length: \(body.count)\r\n\r\n"
        if let data = header.data(using: .utf8) {
            handle.write(data)
        }
        handle.write(body)
    }

    // MARK: - JSON-RPC

    private static func handle(message: [String: Any], service: AgentIOService) -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        // Notifications — no response.
        if id == nil {
            return nil
        }

        switch method {
        case "initialize":
            return ok(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": [
                    "name": "contextday",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                ],
            ])

        case "tools/list", "tools/listChanged":
            return ok(id: id, result: ["tools": toolDescriptors()])

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let data = try AgentIOProtocol.dispatch(tool: name, arguments: args, service: service)
                let text = String(data: data, encoding: .utf8) ?? "[]"
                return ok(id: id, result: [
                    "content": [["type": "text", "text": text]],
                    "isError": false,
                ])
            } catch let err as AgentIOError {
                let payload = (try? JSONSerialization.data(withJSONObject: err.payload))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? err.localizedDescription
                return ok(id: id, result: [
                    "content": [["type": "text", "text": payload]],
                    "isError": true,
                ])
            } catch {
                return rpcError(id: id, code: -32000, message: error.localizedDescription)
            }

        case "ping":
            return ok(id: id, result: [:] as [String: Any])

        default:
            return rpcError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private static func toolDescriptors() -> [[String: Any]] {
        let first: [[String: Any]] = [
            [
                "name": "search_segments",
                "description": "Search ContextDay segments by time / query / track (read-only).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "t0_ms": ["type": "integer"],
                        "t1_ms": ["type": "integer"],
                        "query": ["type": "string"],
                        "track": ["type": "string", "enum": ["mic", "system"]],
                        "page": ["type": "integer"],
                        "max_chars": ["type": "integer"],
                    ],
                ],
            ],
            [
                "name": "get_recent",
                "description": "Recent segments by hours or limit (read-only).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "hours": ["type": "number"],
                        "limit": ["type": "integer"],
                        "track": ["type": "string", "enum": ["mic", "system"]],
                    ],
                ],
            ],
            [
                "name": "get_window",
                "description": "Segments overlapping [t0_ms, t1_ms] (read-only).",
                "inputSchema": [
                    "type": "object",
                    "required": ["t0_ms", "t1_ms"],
                    "properties": [
                        "t0_ms": ["type": "integer"],
                        "t1_ms": ["type": "integer"],
                        "track": ["type": "string", "enum": ["mic", "system"]],
                    ],
                ],
            ],
            [
                "name": "list_activity",
                "description": "Hourly activity buckets (read-only).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "t0_ms": ["type": "integer"],
                        "t1_ms": ["type": "integer"],
                    ],
                ],
            ],
        ]
        return first
    }

    private static func ok(id: Any?, result: [String: Any]) -> [String: Any] {
        var out: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { out["id"] = id }
        return out
    }

    private static func rpcError(id: Any?, code: Int, message: String) -> [String: Any] {
        var out: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id { out["id"] = id }
        return out
    }
}
