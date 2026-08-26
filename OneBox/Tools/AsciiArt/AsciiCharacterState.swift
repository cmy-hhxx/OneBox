struct AsciiCharacterState: Equatable, Sendable {
    private(set) var selection: AsciiCharacterSet = .binary
    private(set) var glyphs = AsciiCharacterSet.binary.glyphs
    private(set) var customInput = "00100101010111"
    private(set) var validation: AsciiCharacterValidation = .valid
    private var lastValidCustomGlyphs = "00100101010111"

    mutating func select(_ selection: AsciiCharacterSet) {
        guard selection != .custom else {
            self.selection = .custom
            glyphs = lastValidCustomGlyphs
            validation = customInput.isEmpty ? .empty : .valid
            return
        }

        self.selection = selection
        glyphs = selection.glyphs
        validation = .valid
    }

    mutating func updateCustom(_ value: String) {
        selection = .custom
        customInput = String(value.prefix(64))
        guard !value.isEmpty else {
            validation = .empty
            return
        }

        glyphs = customInput
        lastValidCustomGlyphs = customInput
        validation = .valid
    }
}
