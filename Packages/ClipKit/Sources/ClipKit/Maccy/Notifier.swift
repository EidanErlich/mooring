// Adapted from Maccy@c376789: Maccy/Notifier.swift
import AppKit

// Maccy posted each copied item's text as a notification (asking for notification permission
// first). Inside Mooring that would put clipboard contents in Notification Center, so it does nothing.
class Notifier {
  static func authorize() {}

  static func notify(body: String?, sound: NSSound?) {}
}
