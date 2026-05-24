import Testing
@testable import MMAudio

@Suite("AudioEngine")
struct AudioEngineTests {

    @Test func enginesStartWithoutCrashing() {
        let engine = AudioEngine()
        engine.start()
        engine.stop()
    }
}
