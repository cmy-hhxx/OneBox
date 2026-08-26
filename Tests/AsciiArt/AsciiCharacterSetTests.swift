import Testing

@testable import AsciiArtTool

@Suite("ASCII character sets")
struct AsciiCharacterSetTests {
    @Test
    func `custom characters preserve unicode order and repeated weighting`() {
        var characters = AsciiCharacterState()

        characters.updateCustom("😀😀A")

        #expect(characters.selection == .custom)
        #expect(characters.glyphs == "😀😀A")
        #expect(characters.validation == .valid)
    }

    @Test
    func `custom characters keep at most sixty four graphemes`() {
        var characters = AsciiCharacterState()

        characters.updateCustom(String(repeating: "界", count: 65))

        #expect(characters.glyphs.count == 64)
    }

    @Test
    func `empty custom input keeps the last valid characters`() {
        var characters = AsciiCharacterState()
        characters.updateCustom("0011")

        characters.updateCustom("")

        #expect(characters.glyphs == "0011")
        #expect(characters.validation == .empty)
    }

    @Test
    func `returning to custom restores the visible custom characters`() {
        var characters = AsciiCharacterState()
        characters.updateCustom("ABC")
        characters.select(.classic)

        characters.select(.custom)

        #expect(characters.selection == .custom)
        #expect(characters.customInput == "ABC")
        #expect(characters.glyphs == "ABC")
        #expect(characters.validation == .valid)
    }
}
