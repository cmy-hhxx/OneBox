import XCTest
@testable import OneBoxDesignSystem

final class LightPaletteTests: XCTestCase {
    @MainActor
    func testLockedLightPaletteMatchesDesignContract() {
        XCTAssertEqual(LightPaletteHex.background, 0xFBFBFA)
        XCTAssertEqual(LightPaletteHex.sidebar, 0xF0F0EE)
        XCTAssertEqual(LightPaletteHex.surface, 0xFFFFFF)
        XCTAssertEqual(LightPaletteHex.surfaceElevated, 0xEEEEEC)
        XCTAssertEqual(LightPaletteHex.selection, 0xE4E4E2)
        XCTAssertEqual(LightPaletteHex.border, 0xD8D8D5)
        XCTAssertEqual(LightPaletteHex.textPrimary, 0x1B1C1E)
        XCTAssertEqual(LightPaletteHex.textSecondary, 0x66676A)
        XCTAssertEqual(LightPaletteHex.accent, 0xBC4535)
        XCTAssertEqual(LightPaletteHex.brandGradientStart, 0x3B6FD8)
        XCTAssertEqual(LightPaletteHex.brandGradientMiddle, 0x8A5CBF)
        XCTAssertEqual(LightPaletteHex.brandGradientEnd, 0xBC4535)
        XCTAssertEqual(LightPaletteHex.positive, 0x087A4B)
        XCTAssertEqual(LightPaletteHex.negative, 0xB42318)
        XCTAssertEqual(LightPaletteHex.warning, 0x8F6400)
        XCTAssertEqual(LightPaletteHex.info, 0x1C587B)
        XCTAssertEqual(LightPaletteHex.infoSurface, 0xE8F3F9)
    }
}
