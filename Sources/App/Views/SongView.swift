import SwiftUI
import MMModels

struct SongView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.15))
            HStack(spacing: 0) {
                songList
                Divider().background(Color.white.opacity(0.15))
                sequencePalette
            }
            Divider().background(Color.white.opacity(0.15))
            footer
        }
        .frame(width: 640, height: 460)
        .background(Color(white: 0.10))
    }

    private var header: some View {
        HStack {
            Text("Song")
                .font(.system(.headline, design: .monospaced, weight: .heavy))
                .foregroundStyle(.white)
            Spacer()
            Text("\(state.project.song.count) sequences")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(14)
    }

    // The ordered song.
    private var songList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ORDER")
                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(state.project.song.enumerated()), id: \.offset) { idx, addr in
                        HStack {
                            Text(String(format: "%02d", idx + 1))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(addr.description)
                                .font(.system(.body, design: .monospaced, weight: .bold))
                                .foregroundStyle(playing(idx) ? Color.black : Color.white)
                            Spacer()
                            Button {
                                state.removeFromSong(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(playing(idx) ? Color.green : Color.white.opacity(0.05),
                                    in: .rect(cornerRadius: 5))
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 300)
    }

    private func playing(_ idx: Int) -> Bool {
        state.transport != .stopped && state.currentSongIndex == idx
    }

    // Filled sequences you can append.
    private var sequencePalette: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ADD A SEQUENCE")
                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(filledSequences(), id: \.self) { addr in
                        Button {
                            state.insertIntoSong(addr)
                        } label: {
                            Text(addr.description)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.cyan.opacity(0.25), in: .rect(cornerRadius: 5))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func filledSequences() -> [PadAddress] {
        var result: [PadAddress] = []
        for bank in BankIndex.allCases {
            for i in 0..<16 {
                let addr = PadAddress(bank: bank, pad: PadIndex(i))
                if let seq = state.project.sequences[addr], !seq.isEmpty { result.append(addr) }
            }
        }
        return result
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { state.playSong() } label: {
                Label("Play Song", systemImage: "play.fill")
            }
            .disabled(state.project.song.isEmpty)

            Button { state.stopTransport() } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            Button { state.flattenSongToNewSequence() } label: {
                Label("Flatten → Sequence", systemImage: "arrow.triangle.merge")
            }
            .disabled(state.project.song.isEmpty)

            Button(role: .destructive) { state.clearSong() } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(state.project.song.isEmpty)

            Spacer()
            Text("Export audio: Play Song + Bounce")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(12)
    }
}
