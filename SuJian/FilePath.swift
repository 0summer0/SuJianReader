import Foundation

enum FilePath {
    static func canonical(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if path.hasPrefix("/private/var/") {
            path = String(path.dropFirst("/private".count))
        }
        return path
    }

    static func canonicalFile(_ url: URL) -> String {
        var path = canonical(url)
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

enum FileIdentity {
    static func key(for url: URL) -> String {
        if let token = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? Data,
           !token.isEmpty {
            return token.base64EncodedString()
        }
        return FilePath.canonical(url)
    }
}
