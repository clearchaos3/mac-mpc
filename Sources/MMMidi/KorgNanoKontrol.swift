import Foundation
import CoreMIDI

/// Wrapper for the original Korg nanoKONTROL (white, 2008-era).
///
/// 9 sliders + 9 knobs + 9 buttons under sliders + 6 transport buttons +
/// 4 scene memory positions. Each scene assigns its own CC numbers to
/// every control. We stream every CC + Note + SysEx and let the caller
/// decide what each one means.
///
/// Explicitly excludes "nanoKONTROL2" — they enumerate separately.
public final class KorgNanoKontrol: @unchecked Sendable {

    public struct Config: Sendable {
        public var deviceNameContains: String = "nanoKONTROL"
        public var excludeNameContains: String = "nanoKONTROL2"
        public var clientName: String = "mac-mpc.nano"
        public var inputPortName: String = "NanoInput"
        public var pollIntervalSeconds: TimeInterval = 1.0
        public init() {}
    }

    public enum Event: Sendable {
        case connected(name: String)
        case disconnected
        case controlChange(channel: UInt8, cc: UInt8, value: UInt8)
        case note(channel: UInt8, note: UInt8, velocity: UInt8, on: Bool)
        case sysEx(bytes: [UInt8])
    }

    public typealias EventHandler = @Sendable (Event) -> Void

    /// True iff `value` is a clean nanoKONTROL button signal — exactly 0
    /// (release) or 127 (press). Continuous controllers sweep intermediate
    /// values; physical buttons only send 0 or 127.
    public static func isCleanButtonValue(_ value: UInt8) -> Bool {
        value == 0 || value == 127
    }

    // MARK: - State

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var source = MIDIEndpointRef()
    private var connected = false
    private var pollTimer: Timer?
    private let config: Config
    private let onEvent: EventHandler

    public init(config: Config = Config(), onEvent: @escaping EventHandler) {
        self.config = config
        self.onEvent = onEvent
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
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
                let me = Unmanaged<KorgNanoKontrol>.fromOpaque(refCon).takeUnretainedValue()
                me.handlePacketList(plistPtr)
            }, unmanaged, &inputPort),
            "MIDIInputPortCreate"
        )

        attemptConnect()
        let timer = Timer(timeInterval: config.pollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.attemptConnect()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }

    private func attemptConnect() {
        let found = findSource(
            named: config.deviceNameContains,
            excluding: config.excludeNameContains
        )
        let nowConnected = (found != nil)

        if nowConnected, !connected {
            if source != 0 { MIDIPortDisconnectSource(inputPort, source) }
            source = found!
            if MIDIPortConnectSource(inputPort, source, nil) == noErr {
                connected = true
                emit(.connected(name: endpointName(source)))
            }
        } else if !nowConnected, connected {
            if source != 0 { MIDIPortDisconnectSource(inputPort, source) }
            source = 0
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
                    let payload = Array(bytes[(i + 1)..<end])
                    emit(.sysEx(bytes: payload))
                    i = end + 1
                } else { i = bytes.count }
                continue
            }
            let type = status & 0xF0
            let channel = status & 0x0F
            switch type {
            case 0xB0:
                guard i + 2 < bytes.count else { i = bytes.count; continue }
                emit(.controlChange(channel: channel, cc: bytes[i + 1], value: bytes[i + 2]))
                i += 3
            case 0x90:
                guard i + 2 < bytes.count else { i = bytes.count; continue }
                let vel = bytes[i + 2]
                emit(.note(channel: channel, note: bytes[i + 1], velocity: vel, on: vel > 0))
                i += 3
            case 0x80:
                guard i + 2 < bytes.count else { i = bytes.count; continue }
                emit(.note(channel: channel, note: bytes[i + 1], velocity: bytes[i + 2], on: false))
                i += 3
            case 0xC0, 0xD0: i += 2
            case 0xA0, 0xE0: i += 3
            default: i += 1
            }
        }
    }

    private func emit(_ event: Event) {
        let handler = onEvent
        DispatchQueue.main.async { handler(event) }
    }
}
