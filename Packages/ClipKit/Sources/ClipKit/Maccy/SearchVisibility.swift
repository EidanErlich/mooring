// Adapted from Maccy@c376789: Maccy/SearchVisibility.swift
import Defaults
import Foundation

enum SearchVisibility: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case always
  case duringSearch

  var id: Self { self }

  var description: String {
    switch self {
    case .always:
      return NSLocalizedString("SearchVisibilityAlways", tableName: "AppearanceSettings", bundle: .module, comment: "")
    case .duringSearch:
      return NSLocalizedString("SearchVisibilityDuringSearch", tableName: "AppearanceSettings", bundle: .module, comment: "")
    }
  }
}
