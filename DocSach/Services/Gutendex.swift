import Foundation

/// Kho sách miễn phí, hợp pháp (sách đã hết bản quyền) của Project Gutenberg,
/// truy cập qua API công khai Gutendex.
struct GutenBook: Decodable, Identifiable {
    struct Person: Decodable { let name: String }

    let id: Int
    let title: String
    let authors: [Person]
    let subjects: [String]
    let formats: [String: String]
    let downloadCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, authors, subjects, formats
        case downloadCount = "download_count"
    }

    var epubURL: URL? {
        let key = formats.keys.first { $0.hasPrefix("application/epub+zip") }
        return key.flatMap { formats[$0] }.flatMap(URL.init(string:))
    }

    var coverURL: URL? { formats["image/jpeg"].flatMap(URL.init(string:)) }

    var authorText: String {
        authors.map { person -> String in
            let parts = person.name.components(separatedBy: ", ")
            return parts.count == 2 ? "\(parts[1]) \(parts[0])" : person.name
        }.joined(separator: ", ")
    }
}

struct GutendexPage: Decodable {
    let count: Int
    let next: String?
    let results: [GutenBook]
}

struct Shelf: Identifiable, Hashable {
    let title: String
    var search: String? = nil
    var topic: String? = nil
    var id: String { title }

    static func shelves(for category: BookCategory) -> [Shelf] {
        switch category {
        case .business:
            return [Shelf(title: "Henry Ford", search: "Henry Ford"),
                    Shelf(title: "Andrew Carnegie", search: "Carnegie autobiography"),
                    Shelf(title: "Benjamin Franklin", search: "Franklin autobiography"),
                    Shelf(title: "Rockefeller", search: "Rockefeller"),
                    Shelf(title: "P. T. Barnum", search: "Barnum money"),
                    Shelf(title: "Tiểu sử", topic: "biography"),
                    Shelf(title: "Kinh doanh", topic: "business")]
        case .detective:
            return [Shelf(title: "Sherlock Holmes", search: "Sherlock Holmes"),
                    Shelf(title: "Agatha Christie", search: "Agatha Christie"),
                    Shelf(title: "Arsène Lupin", search: "Arsene Lupin"),
                    Shelf(title: "Cha Brown", search: "Father Brown"),
                    Shelf(title: "Trinh thám", topic: "detective")]
        case .mystery:
            return [Shelf(title: "Edgar Allan Poe", search: "Edgar Allan Poe"),
                    Shelf(title: "Truyện ma", topic: "ghost stories"),
                    Shelf(title: "Wilkie Collins", search: "Wilkie Collins"),
                    Shelf(title: "Dracula", search: "Bram Stoker"),
                    Shelf(title: "Kinh dị", topic: "horror")]
        case .comics, .other:
            return [Shelf(title: "Phổ biến nhất", topic: "fiction"),
                    Shelf(title: "Phiêu lưu", topic: "adventure")]
        }
    }
}

enum Gutendex {
    static func fetch(shelf: Shelf?, query: String?) async throws -> GutendexPage {
        var comps = URLComponents(string: "https://gutendex.com/books/")!
        var items = [URLQueryItem(name: "mime_type", value: "application/epub")]
        if let q = query, !q.isEmpty {
            items.append(URLQueryItem(name: "search", value: q))
        } else if let shelf {
            if let s = shelf.search { items.append(URLQueryItem(name: "search", value: s)) }
            if let t = shelf.topic { items.append(URLQueryItem(name: "topic", value: t)) }
        }
        comps.queryItems = items
        return try await fetch(url: comps.url!)
    }

    static func fetch(url: URL) async throws -> GutendexPage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 40
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImportError.http(http.statusCode)
        }
        return try JSONDecoder().decode(GutendexPage.self, from: data)
    }
}
