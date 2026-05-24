import SwiftUI
import MMAudio
import MMModels

/// The "LCD" panel: page tabs, header strip, waveform, parameter readouts,
/// and the K1-K3 knobs below. Mirrors the MPC Sample's display layout.
struct DisplayPanelView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 10) {
            displayBox
            knobs
        }
    }

    private var displayBox: some View {
        VStack(spacing: 0) {
            pageTabs
            Divider().background(Color.white.opacity(0.1))
            header
            waveformArea
            paramReadouts
        }
        .background(Color(white: 0.05), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .frame(height: 220)
    }

    private var pageTabs: some View {
        HStack(spacing: 0) {
            ForEach(SamplePage.allCases) { page in
                tabButton(page)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func tabButton(_ page: SamplePage) -> some View {
        let isActive = state.currentPage == page
        return Button {
            state.currentPage = page
        } label: {
            Text(page.label)
                .font(.system(.caption, design: .monospaced, weight: isActive ? .heavy : .regular))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive ? Color.yellow : Color.white.opacity(0.06),
                    in: .rect(cornerRadius: 4)
                )
        }
        .buttonStyle(.plain)
        .padding(2)
    }

    private var header: some View {
        let pad = state.selectedPad
        let padState = state.project.pads[pad]
        let name = padState?.sampleURL?.deletingPathExtension().lastPathComponent ?? "(empty)"
        return HStack(spacing: 12) {
            Text(pad.description)
                .font(.system(.caption, design: .monospaced, weight: .heavy))
                .foregroundStyle(.yellow)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            statusGlyphs(pad: padState)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func statusGlyphs(pad: Pad?) -> some View {
        HStack(spacing: 6) {
            if pad?.loop == true {
                glyph("repeat")
            }
            if pad?.reverse == true {
                glyph("arrow.left")
            }
            if pad?.noteOn == true {
                glyph("music.note")
            }
        }
    }

    private func glyph(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.yellow)
            .frame(width: 18, height: 16)
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 3))
    }

    private var waveformArea: some View {
        let pad = state.project.pads[state.selectedPad] ?? Pad()
        return WaveformView(
            peaks: state.waveformPeaks,
            start: pad.start,
            end: pad.end,
            loopStart: pad.loopStart,
            showLoopMarker: pad.loop
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var paramReadouts: some View {
        HStack(spacing: 0) {
            ForEach(state.currentPageParameters, id: \.label) { p in
                paramZone(label: p.label, value: p.displayValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func paramZone(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 4))
        .padding(.horizontal, 2)
    }

    private var knobs: some View {
        @Bindable var state = state
        let params = state.currentPageParameters
        return HStack(spacing: 28) {
            ForEach(Array(params.enumerated()), id: \.element.label) { idx, p in
                KnobView(
                    label: ["K1", "K2", "K3"][safe: idx] ?? "—",
                    value: Binding(
                        get: { p.normalisedValue },
                        set: { state.setParameter(at: idx, normalised: $0) }
                    ),
                    displayValue: p.displayValue
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
