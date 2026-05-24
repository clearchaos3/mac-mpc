import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            header
            PadGridView()
            statusBar
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 760)
        .background(Color(white: 0.08))
    }

    private var header: some View {
        HStack {
            Text("mac-mpc")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            connectionBadge("MF64", state.mf64Status)
            connectionBadge("nano", state.nanoStatus)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(state.lastEvent)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .frame(height: 22)
    }

    private func connectionBadge(_ label: String, _ status: AppState.ConnectionStatus) -> some View {
        let connected: Bool = { if case .connected = status { true } else { false } }()
        return HStack(spacing: 6) {
            Circle()
                .fill(connected ? .green : .red.opacity(0.7))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: .capsule)
    }
}
