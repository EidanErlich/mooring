// Adapted from Maccy@c376789: Maccy/HighlightMatch.swift
import Foundation
import Defaults

enum HighlightMatch: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case color
  case bold
  case italic
  case underline

  var id: Self { self }

  var description: String {
    switch self {
    case .bold:
      return NSLocalizedString("HighlightMatchBold", tableName: "AppearanceSettings", bundle: .module, comment: "")
    case .color:
      return NSLocalizedString("HighlightMatchColor", tableName: "AppearanceSettings", bundle: .module, comment: "")
    case .italic:
      return NSLocalizedString("HighlightMatchItalic", tableName: "AppearanceSettings", bundle: .module, comment: "")
    case .underline:
      return NSLocalizedString("HighlightMatchUnderline", tableName: "AppearanceSettings", bundle: .module, comment: "")
    }
  }
}
