import Foundation
import SwiftData
import SwiftUI

// MARK: - Chủ đề sách

enum BookCategory: String, CaseIterable, Codable, Identifiable {
    case business, detective, mystery, comics, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .business: return "Doanh nhân"
        case .detective: return "Trinh thám"
        case .mystery: return "Phá án ma mị"
        case .comics: return "Truyện tranh"
        case .other: return "Khác"
        }
    }

    var icon: String {
        switch self {
        case .business: return "briefcase.fill"
        case .detective: return "magnifyingglass"
        case .mystery: return "moon.stars.fill"
        case .comics: return "face.smiling.inverse"
        case .other: return "books.vertical.fill"
        }
    }

    var color: Color {
        switch self {
        case .business: return Color(hex: "2F6FDE")
        case .detective: return Color(hex: "3E7C59")
        case .mystery: return Color(hex: "6B3FA0")
        case .comics: return Color(hex: "E8613C")
        case .other: return Color(hex: "8A6E4B")
        }
    }

    /// Đoán chủ đề từ tên sách, tác giả và thẻ chủ đề trong EPUB.
    static func guess(from text: String, format: BookFormat) -> BookCategory {
        if format == .comic { return .comics }
        let t = text.lowercased()
        let rules: [(BookCategory, [String])] = [
            (.mystery, ["ghost", "horror", "haunted", "vampire", "dracula", "ma quái", "kinh dị", "quỷ", "ma mị", "tâm linh", "poe", "gothic", "supernatural"]),
            (.detective, ["detective", "mystery", "sherlock", "holmes", "crime", "murder", "poirot", "christie", "trinh thám", "phá án", "vụ án", "lupin", "conan doyle"]),
            (.business, ["business", "biography", "autobiography", "ford", "musk", "carnegie", "rockefeller", "economics", "money", "doanh nhân", "kinh doanh", "tiểu sử", "khởi nghiệp", "tỷ phú", "làm giàu"]),
            (.comics, ["comic", "manga", "truyện tranh", "doraemon", "conan"])
        ]
        for (category, words) in rules where words.contains(where: { t.contains($0) }) {
            return category
        }
        return .other
    }
}

enum BookFormat: String, Codable {
    case epub, comic, pdf

    var fileExtension: String {
        switch self {
        case .epub: return "epub"
        case .comic: return "cbz"
        case .pdf: return "pdf"
        }
    }

    var label: String {
        switch self {
        case .epub: return "EPUB"
        case .comic: return "Truyện tranh"
        case .pdf: return "PDF"
        }
    }
}

enum ComicMode: String, CaseIterable, Identifiable {
    case leftToRight, rightToLeft, vertical
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftToRight: return "Lật trái → phải"
        case .rightToLeft: return "Lật phải → trái (manga)"
        case .vertical: return "Cuộn dọc"
        }
    }
}

// MARK: - Sách

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var categoryRaw: String
    var formatRaw: String
    var fileName: String
    @Attribute(.externalStorage) var coverData: Data?
    var addedAt: Date
    var lastOpenedAt: Date?
    var progress: Double
    var positionChapter: Int
    var positionFraction: Double
    var positionPage: Int
    var isFinished: Bool
    var comicModeRaw: String
    var sourceURL: String?
    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book) var bookmarks: [Bookmark] = []

    init(id: UUID, title: String, author: String, category: BookCategory, format: BookFormat,
         fileName: String, coverData: Data?, sourceURL: String?) {
        self.id = id
        self.title = title
        self.author = author
        self.categoryRaw = category.rawValue
        self.formatRaw = format.rawValue
        self.fileName = fileName
        self.coverData = coverData
        self.addedAt = Date()
        self.lastOpenedAt = nil
        self.progress = 0
        self.positionChapter = 0
        self.positionFraction = 0
        self.positionPage = 0
        self.isFinished = false
        self.comicModeRaw = ComicMode.leftToRight.rawValue
        self.sourceURL = sourceURL
    }

    var category: BookCategory {
        get { BookCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var format: BookFormat { BookFormat(rawValue: formatRaw) ?? .epub }

    var comicMode: ComicMode {
        get { ComicMode(rawValue: comicModeRaw) ?? .leftToRight }
        set { comicModeRaw = newValue.rawValue }
    }

    var fileURL: URL { BookStorage.booksDirectory.appendingPathComponent(fileName) }
}

@Model
final class Bookmark {
    var id: UUID
    var createdAt: Date
    var chapter: Int
    var fraction: Double
    var page: Int
    var note: String
    var book: Book?

    init(chapter: Int, fraction: Double, page: Int, note: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.chapter = chapter
        self.fraction = fraction
        self.page = page
        self.note = note
    }
}

// MARK: - Thống kê & khung giờ đọc

@Model
final class ReadingDay {
    @Attribute(.unique) var day: String   // "yyyy-MM-dd"
    var seconds: Double
    var goalMinutes: Int = 30              // mục tiêu của chính ngày đó

    init(day: String, seconds: Double, goalMinutes: Int) {
        self.day = day
        self.seconds = seconds
        self.goalMinutes = goalMinutes
    }

    var minutes: Int { Int(seconds / 60) }
}

/// Mỗi lần mở sách đọc là một phiên, dùng cho lịch sử chi tiết theo ngày.
@Model
final class ReadingSession {
    var day: String
    var startedAt: Date
    var seconds: Double
    var bookTitle: String

    init(day: String, startedAt: Date, seconds: Double, bookTitle: String) {
        self.day = day
        self.startedAt = startedAt
        self.seconds = seconds
        self.bookTitle = bookTitle
    }
}

@Model
final class ReadingSlot {
    var id: UUID
    var hour: Int
    var minute: Int
    var durationMinutes: Int
    var label: String
    var isEnabled: Bool

    init(hour: Int, minute: Int, durationMinutes: Int = 30, label: String = "", isEnabled: Bool = true) {
        self.id = UUID()
        self.hour = hour
        self.minute = minute
        self.durationMinutes = durationMinutes
        self.label = label
        self.isEnabled = isEnabled
    }

    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}
