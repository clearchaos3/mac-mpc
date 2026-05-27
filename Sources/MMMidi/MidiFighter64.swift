import Foundation
import CoreMIDI

/// Wrapper for the DJ TechTools Midi Fighter 64.
///
/// Responsibilities:
///   - Open a Core MIDI client + input/output ports
///   - Find the device by name (with hot-plug polling)
///   - Translate Note On/Off to PadCoord
///   - Drive RGB LEDs via factory-palette Note Ons
///
/// MIDI receive callbacks run on a high-priority Core MIDI thread; the
/// `onEvent` handler is dispatched to the main queue for SwiftUI safety,
/// while `onFastTrigger` (optional) fires synchronously on the MIDI thread
/// for sub-8ms audio triggering.
public final class MidiFighter64: @unchecked Sendable {

    public struct Config: Sendable {
        public var deviceNameContains: String = "Midi Fighter 64"
        public var clientName: String = "flipside.mf64"
        public var inputPortName: String = "Input"
        public var outputPortName: String = "Output"
        public var pollIntervalSeconds: TimeInterval = 1.0
        /// Zero-indexed MIDI channel the MF64 listens on for both pad
        /// presses and LED-set commands. Factory default = 2.
        public var ledChannel: UInt8 = 2
        public init() {}
    }

    public enum Event: Sendable {
        case connected(name: String)
        case disconnected
        case padPressed(PadCoord, note: UInt8, velocity: UInt8)
        case padReleased(PadCoord, note: UInt8)
        case unknownNote(UInt8, velocity: UInt8)
    }

    public typealias EventHandler = @Sendable (Event) -> Void
    public typealias FastTriggerHandler = @Sendable (PadCoord, UInt8) -> Void

    // MARK: - State

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private var connected = false
    private var pollTimer: Timer?
    private let config: Config
    private let onEvent: EventHandler
    private let onFastTrigger: FastTriggerHandler?

    /// The MIDI channel pads actually arrive on (Bank 1 = ch3 / index 2,
    /// Bank 2 = ch2 / index 1). LED control must echo this channel, so we
    /// learn it from incoming Note-Ons and repaint if it changes.
    private var observedChannel: UInt8
    /// Last full grid of colors sent, so we can repaint when the channel is
    /// (re)detected.
    private var lastColors: [PadColor]?

    public init(
        config: Config = Config(),
        onEvent: @escaping EventHandler,
        onFastTrigger: FastTriggerHandler? = nil
    ) {
        self.config = config
        self.onEvent = onEvent
        self.onFastTrigger = onFastTrigger
        self.observedChannel = config.ledChannel
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
        pollTimer?.invalidate()
    }

    public var isConnected: Bool { connected }

    // MARK: - Lifecycle

    public func start() throws {
        try check(
            MIDIClientCreateWithBlock(config.clientName as CFString, &client) { _ in },
            "MIDIClientCreateWithBlock"
        )

        let unmanaged = Unmanaged.passUnretained(self).toOpaque()
        try check(
            MIDIInputPortCreate(client, config.inputPortName as CFString, { plistPtr, refCon, _ in
                guard let refCon else { return }
                let me = Unmanaged<MidiFighter64>.fromOpaque(refCon).takeUnretainedValue()
                me.handlePacketList(plistPtr)
            }, unmanaged, &inputPort),
            "MIDIInputPortCreate"
        )

        try check(
            MIDIOutputPortCreate(client, config.outputPortName as CFString, &outputPort),
            "MIDIOutputPortCreate"
        )

        attemptConnect()
        let timer = Timer(timeInterval: config.pollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.attemptConnect()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }

    private func attemptConnect() {
        let foundSource = findSource(named: config.deviceNameContains)
        let foundDest = findDestination(named: config.deviceNameContains)
        let nowConnected = (foundSource != nil) && (foundDest != nil)

        if nowConnected, !connected {
            if source != 0 { MIDIPortDisconnectSource(inputPort, source) }
            source = foundSource!
            destination = foundDest!
            if MIDIPortConnectSource(inputPort, source, nil) == noErr {
                connected = true
                emit(.connected(name: endpointName(source)))
            }
        } else if !nowConnected, connected {
            if source != 0 { MIDIPortDisconnectSource(inputPort, source) }
            source = 0
            destination = 0
            connected = false
            emit(.disconnected)
        }
    }

    // MARK: - Receive

    private func handlePacketList(_ plistPtr: UnsafePointer<MIDIPacketList>) {
        let plist = plistPtr.pointee
        var packet = plist.packet
        for _ in 0..<plist.numPackets {
            withUnsafeBytes(of: packet.data) { rawBuf in
                let bytes = rawBuf.prefix(Int(packet.length))
                parseMIDIBytes(Array(bytes))
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func parseMIDIBytes(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            let status = bytes[i]
            if status == 0xF0 {
                if let end = bytes[i...].firstIndex(of: 0xF7) {
                    i = end + 1
                } else { i = bytes.count }
                continue
            }
            let type = status & 0xF0
            switch type {
            case 0x90:
                guard i + 2 < bytes.count else { i = bytes.count; continue }
                noteChannelObserved(status & 0x0F)
                let note = bytes[i + 1]
                let velocity = bytes[i + 2]
                if velocity == 0 { handleNoteOff(note: note) }
                else { handleNoteOn(note: note, velocity: velocity) }
                i += 3
            case 0x80:
                guard i + 2 < bytes.count else { i = bytes.count; continue }
                handleNoteOff(note: bytes[i + 1])
                i += 3
            case 0xB0, 0xA0, 0xE0: i += 3
            case 0xC0, 0xD0: i += 2
            default: i += 1
            }
        }
    }

    private func handleNoteOn(note: UInt8, velocity: UInt8) {
        if let pad = MFNoteMap.pad(for: note) {
            onFastTrigger?(pad, velocity)
            emit(.padPressed(pad, note: note, velocity: velocity))
        } else {
            emit(.unknownNote(note, velocity: velocity))
        }
    }

    private func handleNoteOff(note: UInt8) {
        if let pad = MFNoteMap.pad(for: note) {
            emit(.padReleased(pad, note: note))
        }
    }

    /// Learn which channel the device sends on; if it differs from what we're
    /// driving LEDs on, switch and repaint so LED control isn't ignored.
    private func noteChannelObserved(_ channel: UInt8) {
        guard channel != observedChannel else { return }
        observedChannel = channel
        if let colors = lastColors, colors.count == 64 {
            var i = 0
            setAllPadColors { _ in defer { i += 1 }; return colors[i] }
        }
    }

    private func emit(_ event: Event) {
        let handler = onEvent
        DispatchQueue.main.async { handler(event) }
    }

    // MARK: - Send: pad LEDs

    /// Per the MF64 user guide, a Note-On of **velocity 0 disables MIDI
    /// control of color** — the device reverts to its own factory-configured
    /// per-pad color (the stray blues/purples/teals on "empty" pads). We
    /// never want that, so clamp every LED send to a minimum of 1 and keep
    /// the app in full control of every ring.
    @inline(__always)
    private func ledVelocity(_ paletteIndex: UInt8) -> UInt8 { max(1, paletteIndex) }

    public func setPadColor(pad: PadCoord, color: PadColor) {
        guard connected else { return }
        let note = MFNoteMap.note(for: pad)
        let status: UInt8 = 0x90 | (observedChannel & 0x0F)
        sendMIDIBytes([status, note, ledVelocity(color.paletteIndex)], port: outputPort, destination: destination)
    }

    public func setAllPadColors(_ colorFor: (PadCoord) -> PadColor) {
        guard connected else { return }
        let status: UInt8 = 0x90 | (observedChannel & 0x0F)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64 * 3)
        var cache = [PadColor](repeating: .off, count: 64)
        for row in 0..<8 {
            for col in 0..<8 {
                let pad = PadCoord(row: row, col: col)
                let color = colorFor(pad)
                cache[row * 8 + col] = color
                bytes.append(status)
                bytes.append(MFNoteMap.note(for: pad))
                bytes.append(ledVelocity(color.paletteIndex))
            }
        }
        lastColors = cache
        sendMIDIBytes(bytes, port: outputPort, destination: destination)
    }

    public func snapshotEndpoints() -> (sources: [String], destinations: [String]) {
        (listSources(), listDestinations())
    }

    /// One-line state for debugging LED control.
    public var diagnosticSummary: String {
        let dest = destination != 0 ? endpointName(destination) : "(none)"
        return "out=\(dest) ledCh=\(observedChannel + 1) connected=\(connected)"
    }

    /// Clear any per-button animation (set to None) so stored/animated
    /// states don't override our MIDI colors. Animation messages are Note-Ons
    /// on the channel one above the LED channel, note = pad note − 36, with a
    /// velocity in the "None" range (0). See the MF64 user guide, Appendix 2.
    public func clearAnimations() {
        guard connected else { return }
        let animChannel = (observedChannel + 1) & 0x0F
        let status: UInt8 = 0x90 | animChannel
        var bytes: [UInt8] = []
        for row in 0..<8 {
            for col in 0..<8 {
                let note = MFNoteMap.note(for: PadCoord(row: row, col: col))
                bytes.append(status)
                bytes.append(note >= 36 ? note - 36 : note)
                bytes.append(0) // velocity 0 = None animation
            }
        }
        sendMIDIBytes(bytes, port: outputPort, destination: destination)
    }
}
