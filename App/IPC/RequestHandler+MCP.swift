import AwakeKit
import Foundation
import MooringIPC

extension RequestHandler {
    /// The id prefix of the leases MCP clients hold, `mcp-…`.
    static let mcpLeasePrefix = "mcp-"

    /// `caller` as the request names it: a request carrying an MCP client's name comes from that client, an agent,
    /// whatever the ancestry of the MCP server process.
    func identified(_ caller: Caller, client: String?) -> Caller {
        guard let client else { return caller }
        return Caller(uid: caller.uid, pid: caller.pid, identity: .client(MCPClientName.display(client)))
    }

    /// The owner of an MCP client's lease, or nil when the request names no client.
    func mcpOwner(_ client: String?) -> LeaseOwner? {
        client.map { .mcp(client: MCPClientName.display($0)) }
    }

    /// An MCP client's leases, and only those, have `mcp-` ids.
    func checkMCPPrefix(_ id: String, client: String?) throws {
        let isMCPID = id.hasPrefix(Self.mcpLeasePrefix)
        if client != nil && !isMCPID {
            throw WireError(code: .badRequest, message: "MCP leases need an \(Self.mcpLeasePrefix) id")
        }
        if client == nil && isMCPID {
            throw WireError(code: .badRequest, message: "mcp- ids are for MCP clients")
        }
    }
}
