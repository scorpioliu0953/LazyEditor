import SwiftUI

@main
struct LazyEditorApp: App {
    @State private var projectViewModel = ProjectViewModel()

    var body: some Scene {
        WindowGroup {
            MainEditorView()
                .environment(projectViewModel)
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            AppCommands(vm: projectViewModel)
        }
    }
}
