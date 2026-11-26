import Foundation

/// Bộ đọc XML rất gọn để đọc các tệp cấu trúc của EPUB.
final class XNode {
    let name: String              // tên đã bỏ tiền tố (vd "dc:title" -> "title")
    let attributes: [String: String]
    var children: [XNode] = []
    var text: String = ""
    weak var parent: XNode?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// Lấy thuộc tính, chấp nhận cả dạng có tiền tố (vd "epub:type" khi hỏi "type").
    func attr(_ key: String) -> String? {
        if let v = attributes[key] { return v }
        let lower = key.lowercased()
        for (k, v) in attributes {
            let local = k.split(separator: ":").last.map(String.init) ?? k
            if local.lowercased() == lower { return v }
        }
        return nil
    }

    func first(_ localName: String) -> XNode? {
        let target = localName.lowercased()
        for child in children {
            if child.name.lowercased() == target { return child }
            if let found = child.first(localName) { return found }
        }
        return nil
    }

    func all(_ localName: String) -> [XNode] {
        let target = localName.lowercased()
        var result: [XNode] = []
        for child in children {
            if child.name.lowercased() == target { result.append(child) }
            result.append(contentsOf: child.all(localName))
        }
        return result
    }

    var allText: String {
        text + children.map(\.allText).joined()
    }

    func ancestorCount(named localName: String) -> Int {
        var count = 0
        var node = parent
        while let n = node {
            if n.name.lowercased() == localName.lowercased() { count += 1 }
            node = n.parent
        }
        return count
    }
}

final class MiniXMLParser: NSObject, XMLParserDelegate {
    private var stack: [XNode] = []
    private var root: XNode?

    static func parse(_ data: Data) -> XNode? {
        let delegate = MiniXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()   // kể cả khi lỗi giữa chừng vẫn trả phần đã đọc được
        return delegate.root
    }

    static func parse(url: URL) -> XNode? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XNode(name: Self.localName(elementName), attributes: attributeDict)
        if let top = stack.last {
            node.parent = top
            top.children.append(node)
        } else if root == nil {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }
}
