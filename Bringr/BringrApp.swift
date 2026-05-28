import SwiftUI

@main
struct BringrApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: "circle.hexagongrid")
        }
        .menuBarExtraStyle(.menu)

        Window("About Bringr", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Bringr") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "about")
        }
        Divider()
        Button("Quit Bringr") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
