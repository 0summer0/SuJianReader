import Foundation

enum DocumentLink {
    enum Action: Equatable {
        case scroll(String)
        case open(URL, anchor: String?)
        case external(URL)
        case ignore
    }

    // A trailing slash is required to resolve links relative to the document's directory.
    static func baseDirectory(for file: URL) -> URL {
        let directory = file.deletingLastPathComponent()
        if directory.hasDirectoryPath { return directory }
        return URL(fileURLWithPath: directory.path, isDirectory: true)
    }

    static func resolve(_ href: String, from file: URL) -> Action {
        let raw = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !HTMLText.isBlockedURL(raw) else { return .ignore }
        if raw.hasPrefix("#") {
            guard let fragment = safeFragment(String(raw.dropFirst())) else { return .ignore }
            return .scroll(fragment)
        }
        if raw.hasPrefix("/") { return .ignore }

        let (path, fragment) = splitFragment(raw)
        if let scheme = HTMLText.scheme(in: path) {
            switch scheme {
            case "http", "https", "mailto":

                guard let url = URL(string: raw) else { return .ignore }
                return .external(url)
            case "file":
                guard let url = URL(string: path) else { return .ignore }
                return fileAction(url, fragment: fragment, current: file)
            default:
                return .ignore
            }
        }
        guard let resolved = relativeFileURL(path, from: file) else { return .ignore }
        return fileAction(resolved, fragment: fragment, current: file)
    }

    private static func fileAction(_ url: URL, fragment: String?, current: URL) -> Action {
        let target = withoutFragment(url.standardizedFileURL)
        let anchor = fragment.flatMap(safeFragment)
        if sameFile(target, current) {
            return anchor.map { .scroll($0) } ?? .ignore
        }
        guard MarkdownFile.supportsPathExtension(target.pathExtension) else { return .ignore }
        return .open(target, anchor: anchor)
    }

    private static func relativeFileURL(_ path: String, from file: URL) -> URL? {
        let base = baseDirectory(for: file)
        if let url = URL(string: path, relativeTo: base)?.absoluteURL, url.isFileURL {
            return url.standardizedFileURL
        }
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: encoded, relativeTo: base)?.absoluteURL,
              url.isFileURL else { return nil }
        return url.standardizedFileURL
    }

    private static func splitFragment(_ raw: String) -> (String, String?) {
        guard let hash = raw.firstIndex(of: "#") else { return (raw, nil) }
        let path = String(raw[..<hash])
        let fragment = String(raw[raw.index(after: hash)...])
        return (path, fragment.isEmpty ? nil : fragment)
    }

    static func safeFragment(_ raw: String) -> String? {
        let value = raw.removingPercentEncoding ?? raw
        guard !value.isEmpty, value.count <= 200,
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return value
    }

    private static func withoutFragment(_ url: URL) -> URL {
        guard url.fragment != nil, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.fragment = nil
        return components.url ?? url
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        FilePath.canonicalFile(lhs) == FilePath.canonicalFile(rhs)
    }
}
