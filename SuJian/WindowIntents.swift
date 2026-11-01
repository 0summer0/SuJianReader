import SwiftUI

@Observable
final class WindowIntents {
    var openFileTick = 0
    var libraryTick = 0
    var outlineTick = 0
    var searchTick = 0
    var backTick = 0
}

struct SuJianCommands: Commands {
    let store: LibraryStore
    let intents: WindowIntents
    @AppStorage("readingScale") private var readingScale = 1.0

    private var reading: Bool {
        !store.readerPath.isEmpty
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开") { intents.openFileTick += 1 }
        }
        CommandGroup(after: .textEditing) {
            Button("搜索文稿") { intents.searchTick += 1 }
        }

        CommandGroup(replacing: .sidebar) {
            Button("文库") { intents.libraryTick += 1 }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button("返回") { intents.backTick += 1 }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!reading)
            Divider()
            Button("目录") { intents.outlineTick += 1 }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(!reading)
            Button("放大字号") { step(+1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!reading)
            Button("缩小字号") { step(-1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!reading)
            Button("标准字号") { readingScale = 1 }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!reading)
        }
    }

    private func step(_ direction: Int) {
        let values = ReadingScale.options.map(\.value)
        let current = values.enumerated().min { abs($0.element - readingScale) < abs($1.element - readingScale) }?.offset ?? 1
        let next = min(max(current + direction, 0), values.count - 1)
        readingScale = values[next]
    }
}
