import Foundation
import MooringIPC

/// The window tools' definitions. They're relayed with the client's name, so the app counts them as an agent's.
extension MCPTools {
    static let windowDefinitions: [Definition] = [
        Definition(
            name: "list_windows",
            description: "List the running apps with their windows, the screens and every region name arrange_windows accepts. "
                + "Call this before arranging windows.",
            inputSchema: schema(required: [], properties: [:])
        ),
        Definition(
            name: "arrange_windows",
            description: "Move and resize the user's windows with one plan for the whole request. Each placement names an app and "
                + "either a region (such as left-half or maximize) or a frame in fractions of the screen. Every placement gets its "
                + "own result: report any that isn't ok, and ask the user about ambiguous ones. The user may be asked first, "
                + "or may have turned this off in Mooring's settings. Offer undo_arrangement afterwards.",
            inputSchema: schema(required: ["placements"], properties: [
                "placements": .object([
                    "type": .string("array"), "minItems": .int(1), "maxItems": .int(WinPlan.maxPlacements),
                    "description": .string("One entry per window to place."),
                    "items": .object([
                        "type": .string("object"),
                        "required": .array([.string("app")]),
                        "properties": .object([
                            "app": .object([
                                "type": .string("string"), "description": .string("The app's name, such as Safari.")
                            ]),
                            "region": .object([
                                "type": .string("string"),
                                "description": .string("A region name from list_windows, such as left-half, right-half or "
                                    + "maximize. Regions only move and resize windows. Give a region or a frame, not both.")
                            ]),
                            "frame": .object([
                                "type": .string("object"),
                                "description": .string("Fractions of the screen's visible area, origin top left. Use instead of region."),
                                "required": .array(["x", "y", "w", "h"].map(JSONValue.string)),
                                "properties": .object(Dictionary(uniqueKeysWithValues: ["x", "y", "w", "h"].map { key in
                                    (key, JSONValue.object(["type": .string("number"), "minimum": .int(0), "maximum": .int(1)]))
                                }))
                            ]),
                            "screen": .object([
                                "type": .string("string"),
                                "description": .string("main, left, right or a 0-based index. Defaults to the screen the window is on.")
                            ]),
                            "title": .object([
                                "type": .string("string"),
                                "description": .string("Picks the window with this title (any case), or else the one whose "
                                    + "title contains it.")
                            ])
                        ])
                    ])
                ]),
                "launch": .object(["type": .string("boolean"), "description": .string("Open apps that aren't running.")]),
                "preview": .object([
                    "type": .string("boolean"), "description": .string("Show each target frame briefly before moving.")
                ])
            ])
        ),
        Definition(
            name: "undo_arrangement",
            description: "Put the windows of the last arrangement back where they were.",
            inputSchema: schema(required: [], properties: [:])
        ),
        Definition(
            name: "save_layout",
            description: "Save where the frontmost window of each running app is, as a named layout.",
            inputSchema: schema(required: ["name"], properties: [
                "name": .object(["type": .string("string"), "description": .string("The layout's name.")])
            ])
        ),
        Definition(
            name: "apply_layout",
            description: "Arrange windows as a saved layout, opening apps that aren't running. "
                + "Results are per placement, as for arrange_windows.",
            inputSchema: schema(required: ["name"], properties: [
                "name": .object(["type": .string("string"), "description": .string("The layout's name.")])
            ])
        )
    ]
}

// MARK: - Calls

extension MCPSession {
    /// `win.list` goes through the normal client; everything that changes windows through the long-timeout one, since
    /// the app may ask the user, wait its turn and launch apps.
    func perform(window call: MCPTools.Call) async -> JSONValue {
        switch call {
        case .listWindows: return await relay(.winList(WinListArgs(client: wireClient)), through: environment.client)
        case .arrangeWindows(var plan):
            plan.client = wireClient
            return await relay(.winArrange(plan), through: environment.windowClient)
        case .undoArrangement:
            return await relay(.winUndo(WinUndoArgs(client: wireClient)), through: environment.windowClient)
        case .saveLayout(let name):
            return await relay(.winLayout(WinLayoutArgs(action: "save", name: name, client: wireClient)),
                               through: environment.windowClient)
        case .applyLayout(let name):
            return await relay(.winLayout(WinLayoutArgs(action: "apply", name: name, client: wireClient)),
                               through: environment.windowClient)
        default: return MCPTools.failure("Unexpected reply from Mooring")
        }
    }

    /// A placement that isn't `ok` is still a success: the call worked, and the agent reports what happened.
    private func relay(_ args: RequestArgs, through client: any RequestSending) async -> JSONValue {
        switch await send(args, through: client) {
        case .done(let result, let request):
            let structured: JSONValue
            switch result {
            case .winList(let value): structured = JSONValue(encoding: value)
            case .winArrange(let value), .winUndo(let value):
                if case .winUndo = result, value.results.isEmpty {
                    return MCPTools.result(WinText.nothingToUndo, structured: JSONValue(encoding: value))
                }
                structured = JSONValue(encoding: value)
            case .winLayout(let value): structured = JSONValue(encoding: value)
            default: return MCPTools.failure(Self.unexpectedReply)
            }
            return MCPTools.result(humanText(result, for: request), structured: structured)
        case .held(let message), .failed(let message, _):
            return MCPTools.failure(message)
        }
    }
}
