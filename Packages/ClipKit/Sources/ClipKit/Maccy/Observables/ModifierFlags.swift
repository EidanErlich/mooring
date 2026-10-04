// Adapted from Maccy@c376789: Maccy/Observables/ModifierFlags.swift
import AppKit.NSEvent
import Defaults

@Observable
class ModifierFlags {
  var flags: NSEvent.ModifierFlags = []

  // Maccy added the monitor in init, capturing self, so it was never removed. It now runs only while
  // ClipKit runs, and goes with the instance.
  @ObservationIgnored private var monitor: Any?
  var isMonitoring: Bool { monitor != nil }

  private static let instances = NSHashTable<ModifierFlags>.weakObjects()
  private static var monitoringAllowed = false
  /// Monitors added and not yet removed, across all instances.
  private(set) static var monitoringCount = 0

  init() {
    Self.instances.add(self)
    if Self.monitoringAllowed {
      startMonitoring()
    }
  }

  deinit {
    stopMonitoring()
  }

  /// Called by ClipKit's start() and stop().
  static func setMonitoring(_ allowed: Bool) {
    monitoringAllowed = allowed
    // `allObjects` is autoreleased; the pool keeps it from holding instances past this call.
    autoreleasepool {
      for instance in instances.allObjects {
        if allowed {
          instance.startMonitoring()
        } else {
          instance.stopMonitoring()
        }
      }
    }
  }

  private func startMonitoring() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      return event
    }
    Self.monitoringCount += 1
  }

  private func stopMonitoring() {
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
    Self.monitoringCount -= 1
  }
}
