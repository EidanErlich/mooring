import CoreGraphics
import Foundation
import MooringIPC
import WindowKit

/// Screens by the names a plan uses, and conversions between points and fractions.
///
/// Coordinates are `WindowSystem`'s throughout: global points with the origin at the top left of the main screen and
/// y growing down (Accessibility's and CG's), so a screen left of main has negative x. A plan's fractional frame has
/// its origin at the top left of the screen's visible area, so it maps straight on: x = visible.minX + fx × width,
/// y = visible.minY + fy × height. No AppKit (bottom-left) flip is needed anywhere.
enum ScreenPicker {
    struct Failure: Error {
        let reason: String
    }

    static func main(of screens: [WSScreen]) -> WSScreen? {
        screens.first(where: \.isMain) ?? screens.first
    }

    /// The nearest screen whose frame lies entirely left of the main screen's centre.
    static func left(of screens: [WSScreen]) -> WSScreen? {
        guard let main = main(of: screens) else { return nil }
        return screens.filter { $0.index != main.index && $0.frame.maxX <= main.frame.midX }
            .max { $0.frame.maxX < $1.frame.maxX }
    }

    /// The nearest screen whose frame lies entirely right of the main screen's centre.
    static func right(of screens: [WSScreen]) -> WSScreen? {
        guard let main = main(of: screens) else { return nil }
        return screens.filter { $0.index != main.index && $0.frame.minX >= main.frame.midX }
            .min { $0.frame.minX < $1.frame.minX }
    }

    /// `main`, `left`, `right` or a 0-based index (any case, trimmed); nil means the screen `window` is on.
    static func pick(_ name: String?, for window: CGRect, in screens: [WSScreen]) -> Result<WSScreen, Failure> {
        let key = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let found: WSScreen?
        switch key {
        case "": found = screen(containing: window, in: screens)
        case "main": found = main(of: screens)
        case "left":
            guard let screen = left(of: screens) else { return .failure(Failure(reason: "no screen to the left")) }
            found = screen
        case "right":
            guard let screen = right(of: screens) else { return .failure(Failure(reason: "no screen to the right")) }
            found = screen
        default:
            guard key.allSatisfy({ $0.isASCII && $0.isNumber }), let index = Int(key) else {
                return .failure(Failure(reason: "unknown screen “\(name ?? "")” (use main, left, right or an index)"))
            }
            guard let screen = screens.first(where: { $0.index == index }) else { return .failure(Failure(reason: "no screen \(index)")) }
            found = screen
        }
        guard let found else { return .failure(Failure(reason: "no screens")) }
        return .success(found)
    }

    /// The screen holding the frame's centre, else the one it overlaps most, else the main screen.
    static func screen(containing frame: CGRect, in screens: [WSScreen]) -> WSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let holding = screens.first(where: { $0.frame.contains(center) }) {
            return holding
        }
        let overlaps = screens.map { ($0, $0.frame.intersection(frame)) }.filter { !$0.1.isNull && !$0.1.isEmpty }
        if let most = overlaps.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) {
            return most.0
        }
        return main(of: screens)
    }

    /// `main`, `left`, `right` or `other`, by screen index.
    static func positions(of screens: [WSScreen]) -> [Int: String] {
        var positions = Dictionary(uniqueKeysWithValues: screens.map { ($0.index, "other") })
        if let main = main(of: screens) {
            positions[main.index] = "main"
        }
        if let left = left(of: screens) {
            positions[left.index] = "left"
        }
        if let right = right(of: screens) {
            positions[right.index] = "right"
        }
        return positions
    }

    static func rect(_ fraction: WinFrame, in area: CGRect) -> CGRect {
        CGRect(x: area.minX + fraction.x * area.width, y: area.minY + fraction.y * area.height,
               width: fraction.w * area.width, height: fraction.h * area.height)
    }

    /// The rect as fractions of `area`, clamped to 0…1 and rounded to 4 places.
    static func fraction(_ rect: CGRect, in area: CGRect) -> WinFrame {
        func part(_ value: CGFloat, of whole: CGFloat) -> Double {
            guard whole > 0 else { return 0 }
            return (min(max(Double(value / whole), 0), 1) * 10_000).rounded() / 10_000
        }
        return WinFrame(x: part(rect.minX - area.minX, of: area.width), y: part(rect.minY - area.minY, of: area.height),
                        w: part(rect.width, of: area.width), h: part(rect.height, of: area.height))
    }
}

extension WinFrame {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
    }
}
