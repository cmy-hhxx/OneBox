import XCTest

@testable import OneBoxDesignSystem

final class LightPaletteTests: XCTestCase {
    @MainActor
    func testLockedLightPaletteMatchesDesignContract() {
        XCTAssertEqual(LightPaletteHex.background, 0xFFFFFF)
        XCTAssertEqual(LightPaletteHex.sidebar, 0xF7F7F7)
        XCTAssertEqual(LightPaletteHex.surface, 0xFFFFFF)
        XCTAssertEqual(LightPaletteHex.surfaceElevated, 0xF7F7F7)
        XCTAssertEqual(LightPaletteHex.selection, 0xF7F7F7)
        XCTAssertEqual(LightPaletteHex.border, 0xEBEBEB)
        XCTAssertEqual(LightPaletteHex.textPrimary, 0x0A0A0A)
        XCTAssertEqual(LightPaletteHex.textSecondary, 0x737373)
        XCTAssertEqual(LightPaletteHex.accent, 0x2B7FFF)
        XCTAssertEqual(LightPaletteHex.accentPressed, 0x155DFC)
        XCTAssertEqual(LightPaletteHex.textOnAccent, 0xFFFFFF)
        XCTAssertEqual(LightPaletteHex.warningSurface, 0xFFF4DB)
        XCTAssertEqual(LightPaletteHex.negativeSurface, 0xFDECEB)
        XCTAssertEqual(LightPaletteHex.primaryGradientStart, 0x2B7FFF)
        XCTAssertEqual(LightPaletteHex.primaryGradientEnd, 0x155DFC)
        XCTAssertEqual(LightPaletteHex.toggleTrack, 0xEBEBEB)
        XCTAssertEqual(LightPaletteHex.textDisabled, 0xA1A1A1)
        XCTAssertEqual(LightPaletteHex.accentHover, 0x3392FF)
        XCTAssertEqual(LightPaletteHex.accentDeep, 0x1447E6)
        XCTAssertEqual(LightPaletteHex.borderHover, 0xD4D4D4)
        XCTAssertEqual(LightPaletteHex.borderActive, 0xA1A1A1)
        XCTAssertEqual(LightPaletteHex.sliderTrack, 0xEBEBEB)
        XCTAssertEqual(LightPaletteHex.sliderTrackHover, 0xD4D4D4)
        XCTAssertEqual(LightPaletteHex.switchChipStart, 0x2473FE)
        XCTAssertEqual(LightPaletteHex.switchChipEnd, 0x0450E2)
        XCTAssertEqual(LightPaletteHex.brandMarkHost, 0x3569CE)
        XCTAssertEqual(LightPaletteHex.brandMarkCore, 0xFFF1D6)
        XCTAssertEqual(LightPaletteHex.brandGradientStart, 0x3B6FD8)
        XCTAssertEqual(LightPaletteHex.brandGradientMiddle, 0x8A5CBF)
        XCTAssertEqual(LightPaletteHex.brandGradientEnd, 0xBC4535)
        XCTAssertEqual(LightPaletteHex.positive, 0x08754A)
        XCTAssertEqual(LightPaletteHex.negative, 0xB42318)
        XCTAssertEqual(LightPaletteHex.warning, 0x865D00)
        XCTAssertEqual(LightPaletteHex.info, 0x1C587B)
        XCTAssertEqual(LightPaletteHex.infoSurface, 0xE8F3F9)
    }

    @MainActor
    func testSemanticSmallTextHasSufficientContrastOnSelectedSurfaces() {
        for foreground in [
            LightPaletteHex.textPrimary, LightPaletteHex.warning,
            LightPaletteHex.positive, LightPaletteHex.negative,
        ] {
            XCTAssertGreaterThanOrEqual(contrast(foreground, LightPaletteHex.selection), 4.5)
        }
        XCTAssertGreaterThanOrEqual(contrast(LightPaletteHex.textPrimary, 0xDCDCDC), 4.5)
        XCTAssertGreaterThanOrEqual(
            contrast(LightPaletteHex.textSecondary, LightPaletteHex.surface), 4.5)
    }

    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ color: UInt32) -> Double {
            let channels = [
                Double((color >> 16) & 255), Double((color >> 8) & 255), Double(color & 255),
            ]
            .map { value -> Double in
                let value = value / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }

}
