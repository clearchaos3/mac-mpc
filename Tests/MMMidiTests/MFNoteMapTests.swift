import Testing
@testable import MMMidi

@Suite("MFNoteMap")
struct MFNoteMapTests {

    @Test func roundTripAllPads() {
        for row in 0..<8 {
            for col in 0..<8 {
                let pad = PadCoord(row: row, col: col)
                let note = MFNoteMap.note(for: pad)
                #expect(MFNoteMap.pad(for: note) == pad)
            }
        }
    }

    @Test func baseNoteIs36() {
        #expect(MFNoteMap.baseNote == 36)
    }

    @Test func notesOutsideRangeReturnNil() {
        #expect(MFNoteMap.pad(for: 35) == nil)
        #expect(MFNoteMap.pad(for: 100) == nil)
    }
}
