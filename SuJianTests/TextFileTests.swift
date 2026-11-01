import XCTest
@testable import SuJian

final class TextFileTests: XCTestCase {
    private func withFile(_ data: Data, perform: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try perform(url)
    }

    func testUTF16WithAndWithoutBOM() throws {
        let content = "# Title\n正文"
        for (encoding, bom) in [(String.Encoding.utf16LittleEndian, [UInt8(0xff), 0xfe]),
                                (.utf16BigEndian, [UInt8(0xfe), 0xff])] {
            let bytes = try XCTUnwrap(content.data(using: encoding))
            for prefix in [[], bom] {
                try withFile(Data(prefix) + bytes) { url in
                    XCTAssertEqual(try TextFile.read(from: url), content)
                    XCTAssertEqual(TextFile.peekTitle(url: url, fallback: "fallback"), "Title")
                }
            }
        }
    }

    func testGB18030TitleAndBodyUseSameEncoding() throws {
        let content = "# 中文标题\n正文"
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        try withFile(try XCTUnwrap(content.data(using: encoding))) { url in
            XCTAssertEqual(try TextFile.read(from: url), content)
            XCTAssertEqual(TextFile.peekTitle(url: url, fallback: "fallback"), "中文标题")
        }
    }

    func testTitlePreviewHandlesBOMAndTruncatedUTF8Character() throws {
        var data = Data([0xef, 0xbb, 0xbf]) + Data("# 中文标题\n".utf8)
        data.append(Data(repeating: 0x61, count: 16_383 - data.count))
        data.append(contentsOf: "中".utf8)
        try withFile(data) { url in
            XCTAssertEqual(TextFile.peekTitle(url: url, fallback: "fallback"), "中文标题")
        }
    }
}
