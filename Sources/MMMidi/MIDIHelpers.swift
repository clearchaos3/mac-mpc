import Foundation
import CoreMIDI

public enum MIDIClientError: Error, CustomStringConvertible {
    case status(OSStatus, String)

    public var description: String {
        switch self {
        case .status(let s, let context): return "CoreMIDI \(context) failed: status \(s)"
        }
    }
}

@inline(__always)
public func check(_ status: OSStatus, _ context: @autoclosure () -> String) throws {
    guard status == noErr else { throw MIDIClientError.status(status, context()) }
}

/// First source whose display name contains `nameContains` (case-insensitive),
/// optionally rejecting any source whose name contains `excluding`.
public func findSource(named nameContains: String, excluding: String? = nil) -> MIDIEndpointRef? {
    let count = MIDIGetNumberOfSources()
    for i in 0..<count {
        let src = MIDIGetSource(i)
        let name = endpointName(src)
        if !name.localizedCaseInsensitiveContains(nameContains) { continue }
        if let excl = excluding, name.localizedCaseInsensitiveContains(excl) { continue }
        return src
    }
    return nil
}

public func findDestination(named nameContains: String, excluding: String? = nil) -> MIDIEndpointRef? {
    let count = MIDIGetNumberOfDestinations()
    for i in 0..<count {
        let dest = MIDIGetDestination(i)
        let name = endpointName(dest)
        if !name.localizedCaseInsensitiveContains(nameContains) { continue }
        if let excl = excluding, name.localizedCaseInsensitiveContains(excl) { continue }
        return dest
    }
    return nil
}

public func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var unmanaged: Unmanaged<CFString>?
    let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanaged)
    if status == noErr, let cf = unmanaged?.takeRetainedValue() {
        return cf as String
    }
    return ""
}

public func listSources() -> [String] {
    (0..<MIDIGetNumberOfSources()).map { endpointName(MIDIGetSource($0)) }
}

public func listDestinations() -> [String] {
    (0..<MIDIGetNumberOfDestinations()).map { endpointName(MIDIGetDestination($0)) }
}

/// Send raw MIDI bytes (channel-voice or SysEx) to a destination via an output port.
public func sendMIDIBytes(_ bytes: [UInt8],
                          port: MIDIPortRef,
                          destination: MIDIEndpointRef) {
    guard !bytes.isEmpty else { return }
    let bufSize = max(256, bytes.count + 32)
    let raw = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 4)
    defer { raw.deallocate() }
    let plist = raw.assumingMemoryBound(to: MIDIPacketList.self)
    var packetPtr = MIDIPacketListInit(plist)
    bytes.withUnsafeBufferPointer { buf in
        if let base = buf.baseAddress {
            packetPtr = MIDIPacketListAdd(plist, bufSize, packetPtr, 0, bytes.count, base)
        }
    }
    MIDISend(port, destination, plist)
}
