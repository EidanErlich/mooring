// Adapted from Maccy@c376789: Maccy/Extensions/NSSound+Named.swift
import AppKit.NSSound

extension NSSound {
  static let knock = NSSound(
    contentsOf: Bundle.module.url(forResource: "Knock", withExtension: "caf")!, byReference: true)
  static let write = NSSound(
    contentsOf: Bundle.module.url(forResource: "Write", withExtension: "caf")!, byReference: true)
}
