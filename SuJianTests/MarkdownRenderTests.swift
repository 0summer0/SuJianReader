import XCTest
@testable import SuJian

final class MarkdownRenderTests: XCTestCase {
    func testRendersHandbookSyntaxAndEscapesHTML() {
        let source = """
        ---
        title: hidden-token
        ---

        # 标题 <未转义>

        ## `??` 和 `||` 是两件工具

        正文 **粗体**，以及 <script>alert(1)</script>。

        - 普通条目
        - [ ] 未完成
        - [x] 已完成

        | 写法 | 在干什么 |
        | --- | --- |
        | `a<b` | 比较 |
        | `` `共 ${n} 笔` `` | 字符串插值 |

        ```javascript
        const n = a < b
        ```

        [危险](javascript:alert(1))
        [安全](https://example.com)

        ~~删去~~
        """

        let rendered = MarkdownRender.render(source)
        let html = rendered.bodyHTML

        XCTAssertFalse(html.contains("hidden-token"))
        XCTAssertTrue(rendered.hasH1)
        XCTAssertEqual(rendered.h1Text, "标题 <未转义>")
        XCTAssertTrue(html.contains("<h1 id=\"h1\"><span class=\"slug\" id=\"标题-未转义\"></span>标题 &lt;未转义&gt;</h1>"))
        XCTAssertTrue(html.contains("<h2 id=\"h2\"><span class=\"slug\" id=\"-和--是两件工具\"></span><code>??</code> 和 <code>||</code> 是两件工具</h2>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("<strong>粗体</strong>"))
        XCTAssertTrue(html.contains("class=\"task\""))
        XCTAssertTrue(html.contains("class=\"task done\""))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>写法</th>"))
        XCTAssertTrue(html.contains("<code>a&lt;b</code>"))
        XCTAssertTrue(html.contains("<pre data-language=\"javascript\"><code>const n = a &lt; b</code></pre>"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
        XCTAssertTrue(html.contains("<del>删去</del>"))
        XCTAssertTrue(rendered.outline.map(\.text).contains("标题 <未转义>"))
        XCTAssertGreaterThan(rendered.textCount, 10)
    }

    func testStripsByteOrderMarkAndFrontMatter() {
        let source = "\u{feff}---\nnote: x\n---\n\n# 真正的标题\n"
        let rendered = MarkdownRender.render(source)
        XCTAssertEqual(rendered.h1Text, "真正的标题")
        XCTAssertFalse(rendered.bodyHTML.contains("note:"))
    }

    func testTableKeepsEveryRowAndColumnAlignment() {
        let html = MarkdownRender.render("""
        | 左对齐 | 居中 | 右对齐 | 默认 |
        |:-------|:----:|-------:|------|
        | A | B | C | D |
        | 长内容 | 短 | 中等 | E |
        """).bodyHTML

        XCTAssertTrue(html.contains("<th class=\"align-left\">左对齐</th>"))
        XCTAssertTrue(html.contains("<th class=\"align-center\">居中</th>"))
        XCTAssertTrue(html.contains("<th class=\"align-right\">右对齐</th>"))
        XCTAssertTrue(html.contains("<th>默认</th>"))
        XCTAssertTrue(html.contains("<td class=\"align-right\">C</td>"))
        XCTAssertTrue(html.contains("<td class=\"align-left\">长内容</td>"))
        XCTAssertEqual(html.components(separatedBy: "<tr>").count - 1, 3)
    }

    func testTableSpansDropPlaceholderCells() {
        let html = MarkdownRender.render("""
        | 季度 | 一月 | 二月 |
        |------|------|------|
        | Q1 | 横跨两列 ||
        | 计划 | 甲 | 乙 |
        | ^ | 丙 | 丁 |
        """).bodyHTML

        XCTAssertTrue(html.contains("<td colspan=\"2\">横跨两列</td>"))
        XCTAssertTrue(html.contains("<td rowspan=\"2\">计划</td>"))
        XCTAssertFalse(html.contains("<td></td>"))
        XCTAssertFalse(html.contains(">^<"))
    }

    func testFootnotesAreNumberedByFirstReference() {
        let html = MarkdownRender.render("""
        先引用命名的[^note]，再引用数字的[^1]，又一次[^note]。没定义的[^missing]，转义的\\[^1]，代码里的 `[^1]`。

        ```markdown
        [^1]: 代码块里的不是定义
        ```

        [^1]: 数字脚注。
        [^note]: 命名脚注，有空格 也行。

            第二段。
        """).bodyHTML

        XCTAssertTrue(html.contains("<sup class=\"fnref\"><a id=\"fnref-1\" href=\"#fn-1\">1</a></sup>"))
        XCTAssertTrue(html.contains("<a id=\"fnref-2\" href=\"#fn-2\">2</a>"))
        XCTAssertTrue(html.contains("<a id=\"fnref-1-2\" href=\"#fn-1\">1</a>"))
        XCTAssertTrue(html.contains("没定义的[^missing]"))
        XCTAssertTrue(html.contains("转义的[^1]"))
        XCTAssertTrue(html.contains("<code>[^1]</code>"))
        XCTAssertTrue(html.contains("[^1]: 代码块里的不是定义"))
        XCTAssertTrue(html.contains("<li id=\"fn-1\">\n<p>命名脚注，有空格 也行。</p>\n<p>第二段。"))
        XCTAssertTrue(html.contains("href=\"#fnref-1-2\""))
        XCTAssertTrue(html.contains("<li id=\"fn-2\">\n<p>数字脚注。"))
        XCTAssertFalse(html.contains("href=\"数字脚注"))
    }

    func testCallouts() {
        let html = MarkdownRender.render("""
        > [!WARNING]
        > 小心。

        > [!tip]- 自定义 **标题**
        > 收起的内容。

        > [!unknown]
        > 普通引用。
        """).bodyHTML

        let warning = String(localized: "警告")
        XCTAssertTrue(html.contains("<blockquote class=\"callout warning\">\n<p class=\"callout-title\">\(warning)</p>\n<p>小心。</p>"))
        XCTAssertTrue(html.contains("<details class=\"callout tip\">\n<summary class=\"callout-title\">自定义 <strong>标题</strong></summary>"))
        XCTAssertTrue(html.contains("<blockquote>\n<p>[!unknown]"))
    }

    func testHighlightAutolinksAndEscapes() {
        let html = MarkdownRender.render("""
        ==高亮==，==**粗**==，a == b，\\==不是==。

        访问https://example.com/a?b=1。或 www.example.com，写信 me@example.com。[已有链接 https://example.org](https://example.net)
        """).bodyHTML

        XCTAssertTrue(html.contains("<mark>高亮</mark>"))
        XCTAssertTrue(html.contains("<mark><strong>粗</strong></mark>"))
        XCTAssertTrue(html.contains("a == b"))
        XCTAssertTrue(html.contains("==不是=="))
        XCTAssertTrue(html.contains("访问<a href=\"https://example.com/a?b=1\">https://example.com/a?b=1</a>。"))
        XCTAssertTrue(html.contains("<a href=\"https://www.example.com\">www.example.com</a>"))
        XCTAssertTrue(html.contains("<a href=\"mailto:me@example.com\">me@example.com</a>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.net\">已有链接 https://example.org</a>"))
    }

    func testSuperscriptAndSubscript() {
        let html = MarkdownRender.render("""
        E = mc^2^，H~2~O^+^，**x^n+1^**，~~删除~~，~有 空格~，a^b c^，\\^不是^，上标^，中文^，[^未定义]^x^，`x^2^`[^1]

        [^1]: 脚注里 x^2^ 照样是上标
        """).bodyHTML

        XCTAssertTrue(html.contains("E = mc<sup>2</sup>"))
        XCTAssertTrue(html.contains("H<sub>2</sub>O<sup>+</sup>"))
        XCTAssertTrue(html.contains("<strong>x<sup>n+1</sup></strong>"))
        XCTAssertTrue(html.contains("<del>删除</del>"))
        XCTAssertTrue(html.contains("<del>有 空格</del>"))
        XCTAssertTrue(html.contains("a^b c^"))
        XCTAssertTrue(html.contains("^不是^，上标^，中文^"))
        XCTAssertTrue(html.contains("[^未定义]<sup>x</sup>"))
        XCTAssertTrue(html.contains("<code>x^2^</code>"))
        XCTAssertTrue(html.contains("<code>x^2^</code><sup class=\"fnref\">"))
        XCTAssertTrue(html.contains("<p>脚注里 x<sup>2</sup> 照样是上标 <a class=\"backref\""))
    }

    func testSafeHTMLSubset() {
        let html = MarkdownRender.render("""
        按 <kbd>⌘</kbd>，H<sub>2</sub>O，<span style="color:red" onclick="x()">红</span><!-- 注释 -->。

        <div align="center">
          <img src="a.png" width="120" onerror="alert(1)" alt="a &amp; b">
          <a href="javascript:alert(1)">坏链接</a>
        </div>

        <script>alert(1)</script>

        <!-- 整段注释 -->

        [制表符](java&#9;script:alert(1))
        """).bodyHTML

        XCTAssertTrue(html.contains("按 <kbd>⌘</kbd>，H<sub>2</sub>O，<span>红</span>。"))
        XCTAssertTrue(html.contains("<div class=\"align-center\">"))
        XCTAssertTrue(html.contains("<img src=\"a.png\" width=\"120\" alt=\"a &amp; b\">"))
        XCTAssertTrue(html.contains("<a>坏链接</a>"))
        XCTAssertTrue(html.contains("<pre class=\"raw\"><code>&lt;script&gt;"))
        XCTAssertFalse(html.contains("onerror"))
        XCTAssertFalse(html.contains("onclick"))
        XCTAssertFalse(html.contains("注释"))
        XCTAssertFalse(html.contains("javascript"))
        XCTAssertFalse(html.contains("script:"))
    }

    func testRelativeNoteLinksStayAsHrefs() {
        let html = MarkdownRender.render("""
        | 分钟 | 做什么 |
        |---|---|
        | 20–45 | [对照卡](04-示例文稿.md) |

        [路线](../02-示例目录.md#一月)
        """).bodyHTML
        XCTAssertTrue(html.contains("href=\"04-示例文稿.md\""))
        XCTAssertTrue(html.contains("href=\"../02-示例目录.md#一月\""))
    }

    func testHeadingSlugsAndChineseSoftBreaks() {
        let rendered = MarkdownRender.render("""
        ## 9. 表格（Table）
        ## 重复
        ## 重复

        第一行中文
        第二行中文
        English
        words
        """)
        let html = rendered.bodyHTML

        XCTAssertTrue(html.contains("<h2 id=\"h1\"><span class=\"slug\" id=\"9-表格table\"></span>"))
        XCTAssertTrue(html.contains("id=\"重复\""))
        XCTAssertTrue(html.contains("id=\"重复-1\""))
        XCTAssertTrue(html.contains("<p>第一行中文第二行中文\nEnglish\nwords</p>"))
        XCTAssertEqual(rendered.outline.map(\.id), ["h1", "h2", "h3"])
    }

    func testManyDocumentAnchorsResolve() {
        let headings = (1...25).map { "## Section \($0)" }.joined(separator: "\n\n")
        let links = (1...25).map { "[Section \($0)](#section-\($0))" }.joined(separator: "\n")
        let html = MarkdownRender.render(headings + "\n\n" + links).bodyHTML
        let ids = Set(html.matches(of: #/id="([^"]+)"/#).map { String($0.output.1) })
        let targets = html.matches(of: #/href="#([^"]+)"/#).map { String($0.output.1) }
        XCTAssertEqual(targets.count, 25)
        for target in targets {
            XCTAssertTrue(ids.contains(target), "Missing anchor \(target)")
        }
    }
}
