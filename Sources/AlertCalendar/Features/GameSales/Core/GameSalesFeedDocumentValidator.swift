import Foundation

enum GameSalesFeedDocumentValidator {
    static func isSteamSchedule(_ text: String) -> Bool {
        text.contains("documentation_bbcode") && text.contains("bb_subsection")
    }

    static func isXML(_ text: String, root: String) -> Bool {
        let delegate = FeedXMLDelegate()
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.root == root && (root != "rss" || delegate.hasChannel)
    }
}

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    var root: String?
    var hasChannel = false
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if depth == 0 { root = elementName }
        if depth == 1 && elementName == "channel" { hasChannel = true }
        depth += 1
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        depth -= 1
    }
}
