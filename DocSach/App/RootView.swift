import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(ImportCenter.self) private var importer
    @Query private var slots: [ReadingSlot]
    @AppStorage(ReadingStats.goalKey) private var goalMinutes = ReadingStats.defaultGoal
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("Thư viện", systemImage: "books.vertical.fill") }
                .tag(0)
            DiscoverView()
                .tabItem { Label("Khám phá", systemImage: "globe") }
                .tag(1)
            GoalsView()
                .tabItem { Label("Mục tiêu", systemImage: "target") }
                .tag(2)
        }
        .tint(AppTheme.accent)
        .overlay {
            if importer.isWorking {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(importer.status).font(.subheadline).multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(40)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = importer.successMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { importer.successMessage = nil }
                    }
            }
        }
        .animation(.easeInOut, value: importer.successMessage)
        .alert("Có lỗi", isPresented: Binding(
            get: { importer.errorMessage != nil },
            set: { if !$0 { importer.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importer.errorMessage ?? "")
        }
        .onOpenURL { url in
            // Mở tệp EPUB/CBZ/PDF từ ứng dụng Tệp, Safari, Zalo… bằng “Chia sẻ → Đọc Sách”
            tab = 0
            Task {
                if url.isFileURL && url.path.contains("/Documents/Inbox/") {
                    await importer.importDocumentsFolder(context: context)
                } else if url.isFileURL {
                    await importer.importFiles([url], category: nil, context: context)
                } else {
                    await importer.importLink(url.absoluteString, category: nil, context: context)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await importer.importDocumentsFolder(context: context) } }
        }
        .task {
            await importer.importBundledSeedBooks(context: context)
            await importer.importStarterPack(context: context)
            await importer.importDocumentsFolder(context: context)
            // Đảm bảo lịch nhắc luôn khớp với khung giờ đã lưu
            let infos = slots.filter(\.isEnabled).map {
                ReminderScheduler.SlotInfo(id: $0.id, hour: $0.hour, minute: $0.minute,
                                           durationMinutes: $0.durationMinutes, label: $0.label)
            }
            await ReminderScheduler.reschedule(slots: infos, goalMinutes: goalMinutes)
        }
    }
}
