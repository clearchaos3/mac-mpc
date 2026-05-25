import SwiftUI

struct SampleBrowserView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let browser = state.browser
        VStack(spacing: 0) {
            header(browser: browser)
            quickJump(browser: browser)
            Divider().background(Color.white.opacity(0.15))
            list(browser: browser)
            Divider().background(Color.white.opacity(0.15))
            footer(browser: browser)
        }
        .background(Color(white: 0.10))
        .frame(width: 620, height: 480)
        .onKeyPress { press in
            handleKey(press, browser: browser)
        }
        .focusable()
        .onAppear { browser.refresh() }
    }

    private func header(browser: SampleBrowser) -> some View {
        HStack {
            Text("Sample Select")
                .font(.system(.headline, design: .monospaced, weight: .heavy))
                .foregroundStyle(.white)
            Spacer()
            Text(browser.currentDirectory.path(percentEncoded: false))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Toggle(isOn: Binding(
                get: { browser.previewOnHighlight },
                set: { browser.previewOnHighlight = $0 })
            ) {
                Text("Preview")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func quickJump(browser: SampleBrowser) -> some View {
        HStack(spacing: 8) {
            ForEach(browser.quickLocations, id: \.name) { loc in
                Button(loc.name) { browser.navigate(to: loc.url) }
                    .font(.system(.caption, design: .monospaced))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func list(browser: SampleBrowser) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(browser.entries.enumerated()), id: \.element.id) { idx, entry in
                        row(entry: entry, isHighlighted: idx == browser.highlightedIndex)
                            .id(idx)
                            .contentShape(.rect)
                            .onTapGesture(count: 2) {
                                _ = loadOrEnter(entry: entry, browser: browser)
                            }
                            .onTapGesture {
                                browser.highlightedIndex = idx
                            }
                    }
                }
            }
            .onChange(of: browser.highlightedIndex) { _, new in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func row(entry: BrowserEntry, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: entry))
                .frame(width: 16)
                .foregroundStyle(isHighlighted ? Color.black.opacity(0.7) : Color.white.opacity(0.5))
            Text(entry.displayName)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isHighlighted ? Color.black : Color.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.yellow.opacity(0.85) : Color.clear)
    }

    private func icon(for entry: BrowserEntry) -> String {
        switch entry.kind {
        case .parent: return "arrow.turn.up.left"
        case .folder: return "folder.fill"
        case .file:   return "waveform"
        }
    }

    private func footer(browser: SampleBrowser) -> some View {
        let pad = state.selectedPad
        return HStack {
            Text("Target: \(pad.description)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Load") {
                if let entry = browser.highlightedEntry, entry.kind == .file {
                    state.loadHighlightedToSelectedPad()
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(browser.highlightedEntry?.kind != .file)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func handleKey(_ press: KeyPress, browser: SampleBrowser) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            browser.nudge(-1)
            return .handled
        case .downArrow:
            browser.nudge(+1)
            return .handled
        case .return:
            if let entry = browser.highlightedEntry, loadOrEnter(entry: entry, browser: browser) {
                dismiss()
            }
            return .handled
        case .leftArrow:
            // ".." entry, if present, is always row 0
            if browser.entries.first?.kind == .parent {
                browser.highlightedIndex = 0
                _ = browser.activate(browser.entries[0])
            }
            return .handled
        default:
            return .ignored
        }
    }

    /// Returns true if a file was loaded (caller should dismiss).
    private func loadOrEnter(entry: BrowserEntry, browser: SampleBrowser) -> Bool {
        switch entry.kind {
        case .folder, .parent:
            _ = browser.activate(entry)
            return false
        case .file:
            state.loadHighlightedToSelectedPad()
            return true
        }
    }
}
