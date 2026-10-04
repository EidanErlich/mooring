// Adapted from Maccy@c376789: MaccyTests/ColorImageTests.swift
import XCTest
@testable import ClipKit

class ColorImageTests: XCTestCase {
  func testColorImageFromShortHex() {
    XCTAssertNotNil(ColorImage.from("fff"))
  }

  func testColorFromFullHex() {
    XCTAssertNotNil(ColorImage.from("#ff8942"))
  }

  func testColorFromNotHex() {
    XCTAssertNil(ColorImage.from("foo"))
  }
}
