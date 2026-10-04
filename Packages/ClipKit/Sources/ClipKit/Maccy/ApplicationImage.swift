// Adapted from Maccy@c376789: Maccy/ApplicationImage.swift
import Defaults
import SwiftUI

class ApplicationImage {
  fileprivate static let fallbackImage = NSImage(
    systemSymbolName: "questionmark.app.dashed",
    accessibilityDescription: nil
  )!
  private static let retryInterval: TimeInterval = 60 * 60

  let bundleIdentifier: String?
  private var image: NSImage?
  private var lastChecked: Date?
  private var eventSource: (any DispatchSourceFileSystemObject)?

  init(bundleIdentifier: String?, image: NSImage? = nil) {
    self.bundleIdentifier = bundleIdentifier
    self.image = image
  }

  var nsImage: NSImage {
    guard let bundleIdentifier else {
      return Self.fallbackImage
    }

    if let image {
      return image
    }

    // The image has been queried before but since the application has been deleted.
    // Check from time to time if the application has returned.
    if let lastChecked,
      Date().timeIntervalSince(lastChecked) < Self.retryInterval {
      return Self.fallbackImage
    }
    lastChecked = .now

    if let appURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: bundleIdentifier
    ) {
      let img = NSWorkspace.shared.icon(forFile: appURL.path)
      image = img

      let descriptor = open(appURL.path, O_EVTONLY)
      if descriptor == -1 {
        // Logged without the app's path: it would tell which app a copy came from.
        ClipKitLog.logger.debug("Couldn't watch an app's icon: errno \(errno)")
      } else if descriptor > 0 {
        let source = DispatchSource.makeFileSystemObjectSource(
          fileDescriptor: descriptor,
          eventMask: [.write, .delete],
          queue: DispatchQueue.global()
        )
        eventSource = source
        source.setEventHandler {
          DispatchQueue.main.async {
            let event = source.data
            if event.contains(.delete) {
              // File was deleted.
              ClipKitLog.logger.debug("A watched app was deleted")
              source.cancel()
              self.image = nil
              self.lastChecked = nil
            } else if event.contains(.write) {
              // File was modified. Fetch new icon
              ClipKitLog.logger.debug("A watched app was modified")
              self.image = NSWorkspace.shared.icon(forFile: appURL.path)
            }
          }
        }
        source.setCancelHandler {
          close(descriptor)
        }
        source.resume()
      }

      return img
    }

    return Self.fallbackImage
  }
}
