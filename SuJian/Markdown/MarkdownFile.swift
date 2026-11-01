import UniformTypeIdentifiers

enum MarkdownFile {
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    static func supportsPathExtension(_ ext: String) -> Bool {
        extensions.contains(ext.lowercased()) || ext.lowercased() == "txt"
    }

    static var contentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType("net.daringfireball.markdown") {
            types.append(markdown)
        }
        for ext in extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}
