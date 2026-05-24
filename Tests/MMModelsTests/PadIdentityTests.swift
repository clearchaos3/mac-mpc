import Testing
@testable import MMModels

@Suite("PadIdentity")
struct PadIdentityTests {

    @Test func padIndexLabelsMatchMPC() {
        // MPC layout:
        //   13 14 15 16
        //    9 10 11 12
        //    5  6  7  8
        //    1  2  3  4
        #expect(PadIndex(0).label == 1)
        #expect(PadIndex(0).row == 0)
        #expect(PadIndex(0).col == 0)

        #expect(PadIndex(15).label == 16)
        #expect(PadIndex(15).row == 3)
        #expect(PadIndex(15).col == 3)
    }

    @Test func bankIndexLetters() {
        #expect(BankIndex.A.description == "A")
        #expect(BankIndex.H.description == "H")
    }

    @Test func projectStartsWithEverythingPopulated() {
        let project = Project()
        #expect(project.pads.count == 128)
        #expect(project.sequences.count == 128)
        #expect(project.activeSequence == PadAddress(bank: .A, pad: PadIndex(0)))
    }
}
