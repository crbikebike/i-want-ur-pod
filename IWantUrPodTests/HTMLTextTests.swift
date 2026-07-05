import XCTest
import DesignSystem

final class HTMLTextTests: XCTestCase {

    // The exact shape from the Adrift description in the bug report.
    func test_paragraphsAndBreaks_becomeLineBreaks_tagsRemoved() {
        let html = "<p>It's the early 1970s, and a young British family is attempting to sail around the world when catastrophe strikes.</p><p><br></p><p>The Robertsons have sold everything.</p>"
        let out = html.htmlToPlainText()
        XCTAssertFalse(out.contains("<"), "no tags should remain")
        XCTAssertFalse(out.contains(">"))
        XCTAssertTrue(out.hasPrefix("It's the early 1970s"))
        XCTAssertTrue(out.contains("catastrophe strikes."))
        XCTAssertTrue(out.contains("The Robertsons have sold everything."))
        // Paragraphs are separated by a blank line, not jammed together.
        XCTAssertTrue(out.contains("\n"))
        // No 3+ consecutive newlines.
        XCTAssertFalse(out.contains("\n\n\n"))
    }

    func test_decodesNamedAndNumericEntities() {
        XCTAssertEqual("Tom &amp; Jerry".htmlToPlainText(), "Tom & Jerry")
        XCTAssertEqual("5 &lt; 10 &gt; 2".htmlToPlainText(), "5 < 10 > 2")
        XCTAssertEqual("it&#39;s here&hellip;".htmlToPlainText(), "it's here…")
        XCTAssertEqual("caf&#xe9;".htmlToPlainText(), "café")
        XCTAssertEqual("a&mdash;b".htmlToPlainText(), "a—b")
        XCTAssertEqual("we&rsquo;re".htmlToPlainText(), "we\u{2019}re")
    }

    func test_stripsInlineTagsButKeepsText() {
        let html = "Listen to <a href=\"https://x.com\">our <b>best</b> episode</a> now."
        XCTAssertEqual(html.htmlToPlainText(), "Listen to our best episode now.")
    }

    func test_collapsesWhitespaceAndNbsp() {
        let html = "Too    many\t\tspaces&nbsp;&nbsp;here."
        XCTAssertEqual(html.htmlToPlainText(), "Too many spaces here.")
    }

    func test_plainText_isUnchanged_idempotent() {
        let plain = "A perfectly normal sentence with no markup."
        XCTAssertEqual(plain.htmlToPlainText(), plain)
        XCTAssertEqual(plain.htmlToPlainText().htmlToPlainText(), plain)
    }

    func test_unknownEntityIsLeftAlone() {
        XCTAssertEqual("R&D budget".htmlToPlainText(), "R&D budget")
    }

    func test_empty_and_whitespaceOnly() {
        XCTAssertEqual("".htmlToPlainText(), "")
        XCTAssertEqual("<p></p>".htmlToPlainText(), "")
    }
}
