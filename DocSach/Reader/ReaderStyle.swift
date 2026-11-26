import SwiftUI

/// Màu nền giống máy đọc sách: trắng, kem, vàng (sepia) và đêm.
enum ReaderTheme: String, CaseIterable, Identifiable {
    case white, cream, sepia, night
    var id: String { rawValue }

    var name: String {
        switch self {
        case .white: return "Trắng"
        case .cream: return "Kem"
        case .sepia: return "Vàng"
        case .night: return "Đêm"
        }
    }

    var backgroundHex: String {
        switch self {
        case .white: return "FFFFFF"
        case .cream: return "FAF4E6"
        case .sepia: return "F1E3C3"
        case .night: return "141414"
        }
    }

    var textHex: String {
        switch self {
        case .white: return "1C1C1E"
        case .cream: return "2E2A24"
        case .sepia: return "4B3A26"
        case .night: return "CFCAC0"
        }
    }

    var linkHex: String {
        switch self {
        case .night: return "E0A66B"
        default: return "A0521D"
        }
    }

    var background: Color { Color(hex: backgroundHex) }
    var text: Color { Color(hex: textHex) }
    var secondaryText: Color { text.opacity(0.55) }
    var isDark: Bool { self == .night }
}

enum ReaderFont: String, CaseIterable, Identifiable {
    case original, system, serif, palatino, georgia
    var id: String { rawValue }

    var name: String {
        switch self {
        case .original: return "Theo sách"
        case .system: return "San Francisco"
        case .serif: return "Times"
        case .palatino: return "Palatino"
        case .georgia: return "Georgia"
        }
    }

    var css: String? {
        switch self {
        case .original: return nil
        case .system: return "-apple-system, 'Helvetica Neue', sans-serif"
        case .serif: return "'Times New Roman', Times, serif"
        case .palatino: return "Palatino, 'Palatino Linotype', serif"
        case .georgia: return "Georgia, 'Times New Roman', serif"
        }
    }

    var swiftUIFont: Font {
        switch self {
        case .original, .serif: return .custom("Times New Roman", size: 17)
        case .system: return .system(size: 17)
        case .palatino: return .custom("Palatino", size: 17)
        case .georgia: return .custom("Georgia", size: 17)
        }
    }
}

struct ReaderStyle: Equatable {
    var theme: ReaderTheme
    var fontSize: Double
    var lineHeight: Double
    var font: ReaderFont
    var margin: Double

    /// Đoạn JS chèn CSS dàn trang theo cột (mỗi cột = một trang).
    var injectionJS: String {
        let pad = Int(margin)
        let fontRule = font.css.map { "font-family: \($0) !important;" } ?? ""
        let inheritFont = font.css == nil ? "" : "font-family: inherit !important;"
        let css = """
        html { height: 100vh !important; margin: 0 !important; padding: 0 !important; font-size: \(Int(fontSize))px !important; background: #\(theme.backgroundHex) !important; -webkit-text-size-adjust: 100% !important; -webkit-touch-callout: none; }
        body { height: 100vh !important; width: auto !important; max-width: none !important; margin: 0 !important; padding: 28px \(pad)px 28px \(pad)px !important; box-sizing: border-box !important; column-width: calc(100vw - \(pad * 2)px) !important; column-gap: \(pad * 2)px !important; column-fill: auto !important; background: #\(theme.backgroundHex) !important; color: #\(theme.textHex) !important; font-size: \(Int(fontSize))px !important; line-height: \(lineHeight) !important; \(fontRule) text-align: justify; -webkit-hyphens: auto; hyphens: auto; overflow-wrap: break-word; }
        body * { color: inherit !important; background-color: transparent !important; \(inheritFont) }
        p, div, li, span, blockquote { line-height: inherit !important; }
        p { margin-top: 0.3em; margin-bottom: 0.6em; }
        a, a * { color: #\(theme.linkHex) !important; text-decoration: none !important; }
        img, svg, video, image { max-width: 100% !important; max-height: calc(100vh - 64px) !important; height: auto !important; object-fit: contain; break-inside: avoid; -webkit-column-break-inside: avoid; }
        h1, h2, h3, h4 { line-height: 1.3 !important; break-after: avoid; }
        pre { white-space: pre-wrap !important; }
        """
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0] || document.documentElement;
          var m = document.querySelector('meta[name=viewport]');
          if (!m) { m = document.createElement('meta'); m.name = 'viewport'; head.appendChild(m); }
          m.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
          var s = document.getElementById('docsach-style');
          if (!s) { s = document.createElement('style'); s.id = 'docsach-style'; head.appendChild(s); }
          s.textContent = `\(escaped)`;
          document.documentElement.style.width = 'auto';
          return true;
        })();
        """
    }
}
