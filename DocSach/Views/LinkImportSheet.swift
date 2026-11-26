import SwiftUI
import SwiftData

/// Thêm sách bằng cách dán link tải EPUB / CBZ / PDF.
struct LinkImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ImportCenter.self) private var importer

    var initialCategory: BookCategory? = nil
    @State private var link = ""
    @State private var category: BookCategory? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…/sach.epub", text: $link, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        if let text = UIPasteboard.general.string { link = text }
                    } label: {
                        Label("Dán từ bộ nhớ tạm", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Link tải sách")
                } footer: {
                    Text("Hỗ trợ link tải thẳng tệp .epub, .cbz, .pdf. Link Google Drive và Dropbox dạng chia sẻ cũng được tự chuyển thành link tải.")
                }

                Section("Xếp vào mục") {
                    Picker("Chủ đề", selection: $category) {
                        Text("Tự nhận dạng").tag(BookCategory?.none)
                        ForEach(BookCategory.allCases) { c in
                            Label(c.title, systemImage: c.icon).tag(BookCategory?.some(c))
                        }
                    }
                }
            }
            .navigationTitle("Thêm từ link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tải về") {
                        let text = link
                        let chosen = category
                        dismiss()
                        Task { await importer.importLink(text, category: chosen, context: context) }
                    }
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if category == nil { category = initialCategory } }
        }
        .presentationDetents([.medium, .large])
    }
}
