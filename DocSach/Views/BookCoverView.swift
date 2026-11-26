import SwiftUI

struct BookCoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            if let data = book.coverData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderCover(title: book.title, author: book.author, category: book.category)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 4)
    }
}

struct PlaceholderCover: View {
    let title: String
    let author: String
    let category: BookCategory

    var body: some View {
        ZStack {
            LinearGradient(colors: [category.color, category.color.opacity(0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: category.icon).font(.title2)
                Text(title)
                    .font(.system(.footnote, design: .serif).weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                if !author.isEmpty {
                    Text(author).font(.caption2).lineLimit(2).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
        }
    }
}
