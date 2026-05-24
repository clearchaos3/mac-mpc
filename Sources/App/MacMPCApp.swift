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
    }
}
