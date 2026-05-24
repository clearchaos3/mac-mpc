import Testing
import Foundation
@testable import MMModels

@Suite("ProjectStore")
struct ProjectStoreTests {

    @Test func roundTripPreservesEditedPads() throws {
        var project = Project()
        project.name = "TestBeat"
        project.globalBPM = 128

        let a1 = PadAddress(bank: .A, pad: PadIndex(0))
        project.pads[a1]?.sampleURL = URL(fileURLWithPath: "/tmp/kick.wav")
        project.pads[a1]?.start = 0.1
        project.pads[a1]?.end = 0.8
        project.pads[a1]?.semiTune = -5
        project.pads[a1]?.filterType = .lpf4
        project.pads[a1]?.warp = .pitch(percent: 150)

        var seq = MMSequence()
        seq.bpm = 128
        seq.events = [SequenceEvent(tick: 240, bank: .A, pad: PadIndex(0), velocity: 100)]
        project.sequences[a1] = seq

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macmpc-test-\(UUID().uuidString).macmpc")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ProjectStore.save(project, to: dir)
        let loaded = try ProjectStore.load(from: dir)

        #expect(loaded.name == "TestBeat")
        #expect(loaded.globalBPM == 128)
        #expect(loaded.pads[a1]?.start == 0.1)
        #expect(loaded.pads[a1]?.end == 0.8)
        #expect(loaded.pads[a1]?.semiTune == -5)
        #expect(loaded.pads[a1]?.filterType == .lpf4)
        #expect(loaded.pads[a1]?.warp == .pitch(percent: 150))
        #expect(loaded.sequences[a1]?.events.count == 1)
        #expect(loaded.sequences[a1]?.events.first?.tick == 240)
    }

    @Test func loadingMissingBundleThrows() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).macmpc")
        #expect(throws: (any Error).self) {
            _ = try ProjectStore.load(from: dir)
        }
    }
}
