import Foundation

// The `win.*` ops: listing, arranging and undoing windows, and saved layouts. Fields added later decode leniently.

/// A rectangle with its origin at the top left: fractions of a screen's visible area in a plan, points in results.
public struct WinFrame: Codable, Sendable, Equatable {
    // `x`, `y`, `w` and `h` are the wire's field names (docs/SPEC.md).
    // swiftlint:disable identifier_name
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    // swiftlint:enable identifier_name

    public init(x: Double, y: Double, w: Double, h: Double) { // swiftlint:disable:this identifier_name
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// Where one app's window goes: a `region` (a WindowKit action name) or a `frame` (fractions), never both.
/// `screen` is `main`, `left`, `right` or a 0-based index; `title` picks a window by its whole title (any case), or
/// else by a substring of it.
public struct WinPlacement: Codable, Sendable, Equatable {
    /// The `app` that means the frontmost app other than Mooring, which `win do` sends when no app is given.
    public static let frontmostApp = "@frontmost"

    public var app: String
    public var region: String?
    public var frame: WinFrame?
    public var screen: String?
    public var title: String?

    public init(app: String, region: String? = nil, frame: WinFrame? = nil, screen: String? = nil, title: String? = nil) {
        self.app = app
        self.region = region
        self.frame = frame
        self.screen = screen
        self.title = title
    }

    /// This placement with `app` and `region` trimmed (a blank region counts as none) and the frame clamped to 0…1.
    func validated() throws -> WinPlacement {
        var placement = self
        placement.app = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !placement.app.isEmpty else { throw WinPlan.badRequest("Each placement needs an app") }

        placement.region = region.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        switch (placement.region, frame) {
        case (.some, .some): throw WinPlan.badRequest("\(placement.app): give a region or a frame, not both")
        case (nil, nil): throw WinPlan.badRequest("\(placement.app): give a region or a frame")
        default: break
        }

        if let frame {
            let values = [frame.x, frame.y, frame.w, frame.h]
            guard values.allSatisfy(\.isFinite) else { throw WinPlan.badRequest("\(placement.app): frame values must be numbers") }
            let clamped = values.map { min(max($0, 0), 1) }
            placement.frame = WinFrame(x: clamped[0], y: clamped[1], w: clamped[2], h: clamped[3])
        }
        return placement
    }
}

/// One arrangement. `launch` opens apps that aren't running, `preview` shows each target first, and `client` is set
/// only by the MCP server.
public struct WinPlan: Codable, Sendable, Equatable {
    public static let maxPlacements = 32

    public var placements: [WinPlacement]
    public var launch: Bool?
    public var preview: Bool?
    public var client: String?

    public init(placements: [WinPlacement], launch: Bool? = nil, preview: Bool? = nil, client: String? = nil) {
        self.placements = placements
        self.launch = launch
        self.preview = preview
        self.client = client
    }

    /// The plan with every placement checked and tidied, or a `bad_request` naming the first problem.
    public func validated() throws -> WinPlan {
        guard !placements.isEmpty else { throw Self.badRequest("A plan needs at least one placement") }
        guard placements.count <= Self.maxPlacements else {
            throw Self.badRequest("A plan can have at most \(Self.maxPlacements) placements")
        }
        var plan = self
        plan.placements = try placements.map { try $0.validated() }
        return plan
    }

    static func badRequest(_ message: String) -> WireError {
        WireError(code: .badRequest, message: message)
    }
}

/// What happened to one placement.
public enum WinStatus: String, Codable, Sendable, Equatable {
    case ok, partial, ambiguous // swiftlint:disable:this identifier_name
    case notRunning = "not_running", notFound = "not_found"
    case failed
}

/// One placement's outcome. `frame` is the window's final frame in points, `candidates` lists the windows or apps an
/// ambiguous placement could mean, `reason` explains a failure, and `note` adds detail such as "was minimized, restored".
public struct WinPlacementResult: Codable, Sendable, Equatable {
    public var app: String
    public var status: WinStatus
    public var frame: WinFrame?
    public var candidates: [String]?
    public var reason: String?
    public var note: String?

    public init(app: String, status: WinStatus, frame: WinFrame? = nil, candidates: [String]? = nil, reason: String? = nil,
                note: String? = nil) {
        self.app = app
        self.status = status
        self.frame = frame
        self.candidates = candidates
        self.reason = reason
        self.note = note
    }
}

/// The result of `win.arrange`, `win.undo` and a layout's `apply`, one entry per placement in plan order.
public struct WinArrangeResult: Codable, Sendable, Equatable {
    public var results: [WinPlacementResult]
    /// Whether `win.undo` has an arrangement to revert. Absent from older apps, so it decodes to false.
    public var undoAvailable: Bool

    public init(results: [WinPlacementResult], undoAvailable: Bool) {
        self.results = results
        self.undoAvailable = undoAvailable
    }

    enum CodingKeys: String, CodingKey { case results, undoAvailable }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decode([WinPlacementResult].self, forKey: .results)
        undoAvailable = try container.decodeIfPresent(Bool.self, forKey: .undoAvailable) ?? false
    }
}

/// One window in `win.list`. `frame` is in points, origin top left; `screen` is the index of the screen it's on.
public struct WinWindowInfo: Codable, Sendable, Equatable {
    public var id: UInt32
    public var title: String
    public var frame: WinFrame
    public var screen: Int
    public var minimized: Bool
    public var fullScreen: Bool

    public init(id: UInt32, title: String, frame: WinFrame, screen: Int, minimized: Bool, fullScreen: Bool) {
        self.id = id
        self.title = title
        self.frame = frame
        self.screen = screen
        self.minimized = minimized
        self.fullScreen = fullScreen
    }
}

/// One running app in `win.list`, with its windows front to back.
public struct WinAppInfo: Codable, Sendable, Equatable {
    public var name: String
    public var bundleID: String?
    public var pid: Int32
    public var windows: [WinWindowInfo]

    public init(name: String, bundleID: String?, pid: Int32, windows: [WinWindowInfo]) {
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
        self.windows = windows
    }
}

/// One screen in `win.list`. `position` is `main`, `left`, `right` or `other`; `visibleFrame` is in points.
public struct WinScreenInfo: Codable, Sendable, Equatable {
    public var index: Int
    public var name: String
    public var visibleFrame: WinFrame
    public var position: String

    public init(index: Int, name: String, visibleFrame: WinFrame, position: String) {
        self.index = index
        self.name = name
        self.visibleFrame = visibleFrame
        self.position = position
    }
}

/// The result of `win.list`: running apps, screens and every region name a plan accepts.
public struct WinListResult: Codable, Sendable, Equatable {
    public var apps: [WinAppInfo]
    public var screens: [WinScreenInfo]
    /// Absent from older apps, so it decodes to empty.
    public var regions: [String]

    public init(apps: [WinAppInfo], screens: [WinScreenInfo], regions: [String]) {
        self.apps = apps
        self.screens = screens
        self.regions = regions
    }

    enum CodingKeys: String, CodingKey { case apps, screens, regions }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decode([WinAppInfo].self, forKey: .apps)
        screens = try container.decode([WinScreenInfo].self, forKey: .screens)
        regions = try container.decodeIfPresent([String].self, forKey: .regions) ?? []
    }
}

/// `win.layout`: `action` is `save`, `apply`, `list` or `delete`; every action but `list` names a layout.
/// `client` is set only by the MCP server.
public struct WinLayoutArgs: Codable, Sendable, Equatable {
    public var action: String
    public var name: String?
    public var client: String?

    public init(action: String, name: String? = nil, client: String? = nil) {
        self.action = action
        self.name = name
        self.client = client
    }
}

/// `win.undo`: no args from the CLI; `client` is set only by the MCP server.
public struct WinUndoArgs: Codable, Sendable, Equatable {
    public var client: String?

    public init(client: String? = nil) {
        self.client = client
    }
}

/// The result of `win.layout`: the saved layout names, and for `apply`, how the arrangement went.
public struct WinLayoutResult: Codable, Sendable, Equatable {
    public var names: [String]
    public var arrange: WinArrangeResult?

    public init(names: [String], arrange: WinArrangeResult?) {
        self.names = names
        self.arrange = arrange
    }

    enum CodingKeys: String, CodingKey { case names, arrange }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        names = try container.decodeIfPresent([String].self, forKey: .names) ?? []
        arrange = try container.decodeIfPresent(WinArrangeResult.self, forKey: .arrange)
    }
}
