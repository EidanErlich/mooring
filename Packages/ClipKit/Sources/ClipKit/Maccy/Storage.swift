// Adapted from Maccy@c376789: Maccy/Storage.swift
import Foundation
import SwiftData

@MainActor
class Storage {
  enum Location {
    case file(URL)
    case memory
  }

  /// Where `shared` opens the store; `ClipKit.start()` sets it before the first use.
  static var location = Location.memory

  static let shared = ClipKit.track(Storage())

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url: URL

  init() {
    var config = ModelConfiguration(isStoredInMemoryOnly: true)
    url = if case .file(let url) = Storage.location { url } else { URL(filePath: "/dev/null") }

    // Under a test host the store is always in memory.
    if case .file(let url) = Storage.location, !TestHost.isActive {
      config = ModelConfiguration(url: url)
    }

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      // A store that won't open must not take Mooring down; this session's history stays in memory.
      ClipKitLog.logger.error("Cannot load the clipboard store: \(error.localizedDescription)")
      // swiftlint:disable:next force_try
      container = try! ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
  }

  func cleanupOrphanedContents() throws -> Int {
    let descriptor = FetchDescriptor<HistoryItemContent>(
      predicate: #Predicate { $0.item == nil }
    )
    let count = try context.fetchCount(descriptor)
    guard count > 0 else {
      return 0
    }

    try context.delete(
      model: HistoryItemContent.self,
      where: #Predicate { $0.item == nil }
    )
    context.processPendingChanges()
    try context.save()

    return count
  }

  // Titles stored before the sanitization in `HistoryItem.generateTitle()` may
  // contain scalars that hang CoreText on macOS 26. Such an item makes Maccy
  // spin at 100% CPU on every launch without ever drawing its window, so the
  // store has to be healed before the history is first rendered.
  // See https://github.com/p0deje/Maccy/issues/1520.
  func sanitizeTitles() throws -> Int {
    let items = try context.fetch(FetchDescriptor<HistoryItem>())
    var count = 0

    for item in items where item.title.containsScalarsUnsafeForTitleLayout {
      item.title = item.title.removingScalarsUnsafeForTitleLayout()
      count += 1
    }

    guard count > 0 else {
      return 0
    }

    context.processPendingChanges()
    try context.save()

    return count
  }
}
