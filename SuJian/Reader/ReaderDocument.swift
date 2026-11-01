import Foundation

enum ReaderDocument {
    static func html(rendered: RenderedMarkdown, fallbackTitle: String, scale: Double, dark: Bool, wide: Bool = false, topInset: Double = 0) -> String {
        var body = rendered.bodyHTML
        if !rendered.hasH1 {
            body = "<h1 id=\"h0\">\(HTMLText.escape(fallbackTitle))</h1>\n" + body
        }
        let meta = "<p class=\"meta\">\(HTMLText.escape(metaLine(textCount: rendered.textCount)))</p>"
        if let range = body.range(of: "</h1>") {
            body.insert(contentsOf: "\n\(meta)", at: range.upperBound)
        } else {
            body = meta + body
        }
        let theme = dark ? "ink" : "paper"
        let scaleText = String(format: "%.3f", scale)
        return """
        <!DOCTYPE html>
        <html class="\(theme)"\(wide ? " data-wide" : "") style="--scale: \(scaleText); --chrome-top-extra: \(String(format: "%.1f", topInset))px">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article>
        \(body)
        </article>
        </body>
        </html>
        """
    }

    static func metaLine(textCount: Int) -> String {
        if textCount == 0 { return String(localized: "空文稿") }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        let count = formatter.string(from: NSNumber(value: textCount)) ?? "\(textCount)"
        let minutes = max(1, (textCount + 449) / 450)
        return String(localized: "\(count) 字 · 约 \(minutes) 分钟")
    }

    private static let css = #"""
    :root {
      --serif: \#(QuietBeauty.serifStack);
      --sans: -apple-system, "PingFang SC", "Hiragino Sans GB", sans-serif;
      --mono: ui-monospace, "SF Mono", Menlo, monospace;
    }
    \#(QuietBeauty.themeCSS)
    \#(QuietBeauty.headingFaceCSS)
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: var(--bg);
      color: var(--ink);
      font-family: var(--sans);
      font-size: calc(17px * var(--scale, 1));
      line-height: \#(QuietBeauty.bodyLineHeight);
      letter-spacing: \#(QuietBeauty.bodyTracking);
      -webkit-text-size-adjust: 100%;
      overflow-anchor: none; /* Prevent browser scroll anchoring from interfering with position restoration. */
    }
    body { min-height: 100%; }
    article {
      max-width: 40rem;
      margin: 0 auto;
      padding: 4.6rem 1.45rem 4.5rem;
      padding-top: calc(4.6rem + var(--chrome-top-extra, 0px));
    }
    html[data-wide], html[data-wide] body { font-size: calc(18px * var(--scale, 1)); }
    html[data-wide] article {
      max-width: none;
      width: auto;
      padding-left: clamp(2rem, 4vw, 3.5rem);
      padding-right: clamp(2rem, 4vw, 3.5rem);
    }
    html[data-wide] th, html[data-wide] td { max-width: none; }
    /* Wide viewports may still use compact size classes. */
    @media (min-width: 700px) {
      article {
        max-width: none;
        padding-left: clamp(1.45rem, 2.6vw, 2.4rem);
        padding-right: clamp(1.45rem, 2.6vw, 2.4rem);
      }
      th, td { max-width: none; }
    }
    ::selection { background: var(--select); }
    h1, h2, h3, h4, h5, h6 {
      font-family: "Suxuan Heading", var(--serif);
      font-weight: 400;
      line-height: \#(QuietBeauty.headingLineHeight);
      letter-spacing: \#(QuietBeauty.headingTrackingCSS);
      overflow-wrap: break-word;
    }
    h1 { font-size: \#(QuietBeauty.heading1Size); margin: \#(QuietBeauty.heading1Margin); }
    h2 { font-size: \#(QuietBeauty.heading2Size); margin: 2.2rem 0 0.7rem; }
    h3 { font-size: \#(QuietBeauty.heading3Size); margin: 1.6rem 0 0.45rem; }
    h4 { font-size: \#(QuietBeauty.heading4Size); margin: 1.3rem 0 0.4rem; }
    h5 { font-size: \#(QuietBeauty.heading5Size); margin: 1.15rem 0 0.35rem; }
    h6 { font-size: \#(QuietBeauty.heading6Size); margin: 1.05rem 0 0.3rem; }
    p { margin: 0.85rem 0; overflow-wrap: break-word; }
    .meta {
      font-family: var(--sans);
      font-size: 0.72rem;
      letter-spacing: 0.16em;
      color: var(--soft);
      margin: 0 0 1.75rem;
    }
    a {
      color: var(--bronze);
      text-underline-offset: 0.18em;
      text-decoration-thickness: 1px;
      overflow-wrap: anywhere;
    }
    strong { font-weight: 600; }
    del { color: var(--soft); }
    blockquote {
      margin: 1.15rem 0;
      padding: 0.05rem 0 0.05rem 0.95rem;
      border-left: 1px solid var(--bronze);
      color: var(--quote);
      overflow-wrap: break-word;
    }
    blockquote p { margin: 0.35rem 0; }
    hr { border: 0; border-top: 1px solid var(--line); margin: 2rem 0; }
    ul, ol { margin: 0.75rem 0; padding-left: 1.3rem; }
    li { margin: 0.32rem 0; padding-left: 0.15rem; overflow-wrap: break-word; }
    li > ul, li > ol { margin: 0; }
    li > p { margin: 0.2rem 0; }
    li > p:first-child { margin-top: 0; }
    li > p:last-child { margin-bottom: 0; }
    li.task { list-style: none; margin-left: -0.15rem; }
    li.task > p:first-of-type { display: inline; margin: 0; }
    li.task .box {
      display: inline-block;
      width: 0.78em;
      height: 0.78em;
      margin-right: 0.45em;
      border: 1px solid var(--bronze);
      transform: translateY(0.08em);
      position: relative;
      vertical-align: baseline;
    }
    li.task.done .box::after {
      content: "";
      position: absolute;
      left: 0.22em;
      top: 0.02em;
      width: 0.22em;
      height: 0.42em;
      border: solid var(--bronze);
      border-width: 0 1.5px 1.5px 0;
      transform: rotate(40deg);
    }
    code { font-family: var(--mono); font-size: 0.86em; letter-spacing: 0; }
    :not(pre) > code {
      background: var(--code-bg);
      padding: 0.08em 0.34em;
      border-radius: 2px;
      overflow-wrap: break-word;
    }
    pre {
      background: var(--code-bg);
      border: 1px solid var(--code-rule);
      margin: 1.1rem 0;
      padding: 0.95rem 1rem 1rem;
      overflow-x: auto;
      max-width: 100%;
      border-radius: \#(QuietBeauty.codeRadius);
    }
    pre[data-language]::before {
      content: attr(data-language);
      display: block;
      margin-bottom: 0.65rem;
      font-family: var(--mono);
      font-size: 0.68rem;
      letter-spacing: \#(QuietBeauty.codeLabelTracking);
      text-transform: lowercase;
      color: var(--soft);
    }
    pre code {
      font-size: 0.82rem;
      line-height: 1.55;
      background: transparent;
      padding: 0;
      white-space: pre;
    }
    .table-wrap { overflow-x: auto; margin: 1.15rem 0 1.35rem; max-width: 100%; }
    table {
      border-collapse: collapse;
      border-spacing: 0;
      width: max-content;
      min-width: 100%;
      font-size: 0.92rem;
      line-height: 1.55;
    }
    /* Cell borders can overlap or misalign when rows span multiple cells. */
    th, td {
      text-align: left;
      vertical-align: top;
      max-width: 18rem;
      padding: 0.55rem 0.9rem 0.55rem 0;
      border: 0;
      background-image: linear-gradient(var(--hairline), var(--hairline));
      background-size: 100% 1px;
      background-position: left bottom;
      background-repeat: no-repeat;
      word-break: normal;
      overflow-wrap: break-word;
    }
    th {
      font-family: "Suxuan Heading", var(--serif);
      font-weight: 600;
      background-image: linear-gradient(var(--rule-solid), var(--rule-solid));
    }
    td p, th p { margin: 0; }
    td code, th code { overflow-wrap: break-word; word-break: normal; }
    :where(th, td)[colspan] { text-align: center; }
    :where(th, td)[rowspan] { vertical-align: middle; }
    .align-left { text-align: left; }
    .align-center { text-align: center; }
    .align-right { text-align: right; }
    .align-justify { text-align: justify; }
    img { max-width: 100%; height: auto; margin: 0.8rem 0; }
    .raw { white-space: pre-wrap; }
    sup, sub { line-height: 0; }
    mark {
      background: var(--mark);
      color: inherit;
      padding: 0.04em 0.12em;
      border-radius: 2px;
    }
    ins {
      text-decoration: underline;
      text-decoration-color: var(--bronze);
      text-underline-offset: 0.2em;
    }
    abbr[title] {
      text-decoration: underline dotted;
      text-underline-offset: 0.2em;
    }
    kbd {
      font-family: var(--mono);
      font-size: 0.8em;
      padding: 0.06em 0.42em;
      border: 1px solid var(--line);
      border-bottom-width: 2px;
      border-radius: 3px;
      background: var(--code-bg);
      white-space: nowrap;
    }
    ruby rt {
      font-family: var(--sans);
      font-size: 0.56em;
      color: var(--soft);
    }
    dt { font-weight: 600; margin-top: 0.8rem; }
    dd { margin: 0.2rem 0 0.6rem 1.3rem; }
    figure { margin: 1.2rem 0; }
    figcaption { font-size: 0.82rem; color: var(--soft); text-align: center; }
    details {
      margin: 1.1rem 0;
      padding: 0.55rem 0.9rem;
      border: 1px solid var(--line);
      border-radius: 2px;
    }
    details > summary {
      color: var(--bronze);
      cursor: pointer;
    }
    details[open] > summary { margin-bottom: 0.4rem; }
    details > :last-child { margin-bottom: 0.2rem; }
    .callout {
      --callout: var(--note);
      margin: 1.15rem 0;
      padding: 0.15rem 0 0.15rem 0.95rem;
      border: 0;
      border-left: 2px solid var(--callout);
      border-radius: 0;
      color: var(--ink);
    }
    .callout.tip { --callout: var(--tip); }
    .callout.important { --callout: var(--important); }
    .callout.warning { --callout: var(--warning); }
    .callout.caution { --callout: var(--caution); }
    .callout p { margin: 0.35rem 0; }
    .callout .callout-title {
      font-family: var(--sans);
      font-size: 0.8rem;
      font-weight: 600;
      letter-spacing: 0.12em;
      color: var(--callout);
      margin: 0.3rem 0 0.25rem;
    }
    sup.fnref {
      font-family: var(--sans);
      font-size: 0.75em;
    }
    sup.fnref a {
      text-decoration: none;
      padding: 0 0.2em;
    }
    .footnotes {
      margin-top: 3rem;
      padding-top: 0.7rem;
      border-top: 1px solid var(--line);
      font-size: 0.86rem;
      line-height: 1.65;
      color: var(--quote);
    }
    .footnotes-title {
      font-size: 0.8rem;
      letter-spacing: 0.16em;
      color: var(--soft);
      margin: 0.4rem 0 0.2rem;
    }
    .footnotes ol { padding-left: 1.4rem; }
    .footnotes li > p { margin: 0.25rem 0; }
    a.backref {
      font-family: var(--sans);
      text-decoration: none;
      margin-left: 0.1em;
    }
    """#
}
