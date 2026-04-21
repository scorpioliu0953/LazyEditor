import SwiftUI

struct AppCommands: Commands {
    let vm: ProjectViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("開啟專案⋯") {
                vm.openProject()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("儲存專案") {
                vm.saveProject()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("另存新檔⋯") {
                vm.saveProjectAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("匯入影片…") {
                vm.showImportPanel()
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("復原") {
                vm.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!vm.timeline.canUndo)
        }

        CommandMenu("編輯工具") {
            Button("選取工具") {
                vm.toolMode = .selection
            }
            .keyboardShortcut("a", modifiers: [])

            Button("剪刀工具") {
                vm.toolMode = .blade
            }
            .keyboardShortcut("b", modifiers: [])

            Divider()

            Button("刪除選取片段") {
                vm.deleteSelectedSegments()
            }
            .keyboardShortcut(.delete, modifiers: [])

            Divider()

            Button("一鍵去除靜音") {
                vm.removeAllSilence()
            }
        }

        CommandMenu("播放") {
            Button(vm.playback.isPlaying ? "暫停" : "播放") {
                vm.playback.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(vm.isEditingTextCard)
        }
    }
}
