// HTMLText — feed HTML → readable plain text (display-layer only).
// Composed utility; no design/kit source. Podcast/episode descriptions keep
// their raw HTML in the model on purpose (docs/spec/feed-field-mapping.md:
// "keep the raw feed string; the detail screen decides how to render/strip").
// This is that strip step, applied where feed copy is rendered (ExpandableText
// call sites in the detail screen) rather than in the parser.
import Foundation

public extension String {
    /// Converts feed HTML/escaped body copy into readable plain text:
    /// block-level tags (`<br>`, `</p>`, `</div>`, `</li>`, headings) become
    /// line breaks, all other tags are removed, HTML entities (named + numeric)
    /// are decoded, and runs of whitespace are collapsed. Idempotent on
    /// already-plain text.
    func htmlToPlainText() -> String {
        var s = self

        // 1. Block-level tags → a single newline (paragraph/line breaks).
        let breakPatterns = [
            "<br\\s*/?>", "</p\\s*>", "</div\\s*>", "</li\\s*>",
            "</h[1-6]\\s*>", "</tr\\s*>", "</blockquote\\s*>"
        ]
        for pattern in breakPatterns {
            s = s.replacingOccurrences(
                of: pattern, with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // 2. Remove every remaining tag.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // 3. Decode HTML entities.
        s = s.decodingHTMLEntities()

        // 4. Collapse whitespace: horizontal runs → one space; trim around
        //    newlines; 3+ blank lines → one blank line.
        s = s.replacingOccurrences(of: "[ \\t\\x{00A0}]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes named and numeric HTML entities (`&amp;`, `&#39;`, `&#x2019;`).
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }

        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "nbsp": " ", "hellip": "…", "mdash": "—", "ndash": "–",
            "rsquo": "\u{2019}", "lsquo": "\u{2018}", "ldquo": "\u{201C}",
            "rdquo": "\u{201D}", "copy": "©", "reg": "®", "trade": "™",
            "deg": "°", "middot": "·", "bull": "•", "eacute": "é",
            "egrave": "è", "agrave": "à", "ccedil": "ç", "uuml": "ü",
            "ouml": "ö", "auml": "ä"
        ]

        var result = ""
        result.reserveCapacity(count)
        var index = startIndex

        while index < endIndex {
            let char = self[index]
            guard char == "&" else {
                result.append(char)
                index = self.index(after: index)
                continue
            }
            // Find the terminating ';' within a short window.
            guard let semi = self[index...].firstIndex(of: ";"),
                  distance(from: index, to: semi) <= 12 else {
                result.append(char)
                index = self.index(after: index)
                continue
            }
            let entity = String(self[self.index(after: index)..<semi]) // between & and ;
            var decoded: String?

            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                if let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                    decoded = String(scalar)
                }
            } else if entity.hasPrefix("#") {
                if let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                    decoded = String(scalar)
                }
            } else {
                decoded = named[entity]
            }

            if let decoded {
                result.append(decoded)
                index = self.index(after: semi)
            } else {
                // Unknown entity — leave the '&' as-is and continue.
                result.append(char)
                index = self.index(after: index)
            }
        }
        return result
    }
}
