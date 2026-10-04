// Adapted from Maccy@c376789: Maccy/Extensions/KeyboardShortcuts.Name+Shortcuts.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = ClipKitShortcuts.guarded(
    Self(ClipKitShortcuts.popupRawValue, default: Shortcut(.c, modifiers: [.command, .shift])),
    registeredWhile: { ClipKitShortcuts.popupActive }
  )
  static let pin = ClipKitShortcuts.guarded(Self("clipboardPin", default: Shortcut(.p, modifiers: [.option])))
  static let delete = ClipKitShortcuts.guarded(Self("clipboardDelete", default: Shortcut(.delete, modifiers: [.option])))
  static let togglePreview = ClipKitShortcuts.guarded(
    Self("clipboardTogglePreview", default: Shortcut(.space, modifiers: [.control]))
  )
}
