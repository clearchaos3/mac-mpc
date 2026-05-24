import SwiftUI

@main
struct MacMPCApp: App {

    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("mac-mpc") {
            ContentView()
                .environment(state)
                .task { state.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { state.newProject() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Open Project…") { state.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: [.command])
                Divider()
                Button("Save Project…") { state.saveProject() }
                    .keyboardShortcut("s", modifiers: [.command])
            }
        }
    }
}
