import SwiftUI
import MMAudio

/// Renders a waveform from pre-extracted peaks. Overlays start/end/loop
/// markers as normalised positions [0, 1].
struct WaveformView: View {
    let peaks: WaveformPeaks
    var start: Double = 0
    var end: Double = 1
    var loopStart: Double = 0
    var showLoopMarker: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.04))

                if !peaks.peaks.isEmpty {
                    // Filled bars (a path of thin rects). Filling line segments
                    // paints nothing, so each bin is drawn as a rectangle.
                    waveformShape(in: geo.size)
                        .fill(Color(red: 0.95, green: 0.78, blue: 0.36))
                }

                // Inactive regions overlay (darken before start / after end).
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: geo.size.width * start)
                    .position(x: (geo.size.width * start) / 2,
                              y: geo.size.height / 2)

                let endX = geo.size.width * end
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: max(0, geo.size.width - endX))
                    .position(x: endX + (geo.size.width - endX) / 2,
                              y: geo.size.height / 2)

                // Start / end markers.
                marker(at: start, in: geo.size, color: .green, label: "S")
                marker(at: end,   in: geo.size, color: .red,   label: "E")
                if showLoopMarker {
                    marker(at: loopStart, in: geo.size, color: .cyan, label: "L")
                }
            }
        }
    }

    private func waveformShape(in size: CGSize) -> Path {
        Path { p in
            let bins = peaks.peaks.count
            guard bins > 0 else { return }
            let midY = size.height / 2
            let stepX = size.width / CGFloat(bins)
            let barW = max(1, stepX)
            for i in 0..<bins {
                let pk = peaks.peaks[i]
                let x = CGFloat(i) * stepX
                let topY = midY - CGFloat(pk.y) * midY     // peaks.y = max (>=0)
                let botY = midY - CGFloat(pk.x) * midY     // peaks.x = min (<=0)
                let h = max(1, botY - topY)
                p.addRect(CGRect(x: x, y: topY, width: barW, height: h))
            }
        }
    }

    private func marker(at position: Double, in size: CGSize, color: Color, label: String) -> some View {
        let x = size.width * position
        return ZStack {
            Rectangle()
                .fill(color)
                .frame(width: 1.5)
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(color, in: .rect(cornerRadius: 2))
                .offset(y: -size.height / 2 + 6)
        }
        .frame(width: 1.5, height: size.height)
        .position(x: x, y: size.height / 2)
    }
}
