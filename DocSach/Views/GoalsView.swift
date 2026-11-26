import SwiftUI
import SwiftData
import Charts
import UserNotifications

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query private var days: [ReadingDay]
    @Query(sort: [SortDescriptor(\ReadingSlot.hour), SortDescriptor(\ReadingSlot.minute)]) private var slots: [ReadingSlot]
    @AppStorage(ReadingStats.goalKey) private var goalMinutes = ReadingStats.defaultGoal

    @State private var editingSlot: ReadingSlot?
    @State private var showNewSlot = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var todayMinutes: Int {
        let key = ReadingStats.key(for: Date())
        return Int((days.first { $0.day == key }?.seconds ?? 0) / 60)
    }

    private struct DayStat: Identifiable {
        let id: String
        let label: String
        let minutes: Double
    }

    private var lastSevenDays: [DayStat] {
        let map = Dictionary(days.map { ($0.day, $0.seconds) }, uniquingKeysWith: +)
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEEE"
        return (0..<7).reversed().compactMap { offset -> DayStat? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = ReadingStats.key(for: date)
            let label = offset == 0 ? "Nay" : f.string(from: date)
            return DayStat(id: key, label: label, minutes: (map[key] ?? 0) / 60)
        }
    }

    /// Thay đổi bất kỳ ở khung giờ → lên lịch nhắc lại.
    private var scheduleSignature: String {
        slots.map { "\($0.id)\($0.hour):\($0.minute)\($0.isEnabled)\($0.label)\($0.durationMinutes)" }.joined()
            + "|\(goalMinutes)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section { todayRing }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                Section("Mục tiêu mỗi ngày") {
                    Stepper(value: $goalMinutes, in: 5...300, step: 5) {
                        Label("\(goalMinutes) phút", systemImage: "flag.checkered")
                    }
                    HStack {
                        Label("Chuỗi ngày đạt mục tiêu", systemImage: "flame.fill").foregroundStyle(.orange)
                        Spacer()
                        Text("\(ReadingStats.streak(days: days, goalMinutes: goalMinutes)) ngày").bold()
                    }
                }

                Section("Thống kê") {
                    HStack {
                        Label("Tổng thời gian đã đọc", systemImage: "hourglass")
                        Spacer()
                        Text(ReadingStats.durationText(minutes: days.reduce(0) { $0 + $1.minutes })).bold()
                    }
                    HStack {
                        Label("Số ngày đạt mục tiêu", systemImage: "checkmark.seal.fill")
                        Spacer()
                        Text("\(days.filter { $0.minutes >= $0.goalMinutes }.count) ngày").bold()
                    }
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Lịch sử đọc theo lịch", systemImage: "calendar")
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                Section("7 ngày qua") {
                    Chart {
                        ForEach(lastSevenDays) { d in
                            BarMark(x: .value("Ngày", d.label), y: .value("Phút", d.minutes))
                                .foregroundStyle(d.minutes >= Double(goalMinutes) ? Color.green : AppTheme.accent)
                                .cornerRadius(4)
                        }
                        RuleMark(y: .value("Mục tiêu", Double(goalMinutes)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 160)
                    .padding(.vertical, 6)
                }

                Section {
                    if slots.isEmpty {
                        Text("Chưa có khung giờ nào. Thêm vài khung giờ trong ngày, ví dụ 6:30 sáng, 12:30 trưa, 21:00 tối.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(slots) { slot in
                        SlotRow(slot: slot) { editingSlot = slot }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(slots[i]) }
                        try? context.save()
                    }
                    Button { showNewSlot = true } label: { Label("Thêm khung giờ đọc", systemImage: "plus.circle.fill") }
                } header: {
                    Text("Khung giờ đọc")
                } footer: {
                    Text("Ứng dụng sẽ nhắc bạn trước mỗi khung giờ 10 phút, mỗi ngày.")
                }

                Section("Thông báo") {
                    if notificationStatus == .denied {
                        Label("Thông báo đang bị tắt", systemImage: "bell.slash.fill").foregroundStyle(.red)
                        Button("Mở Cài đặt để bật") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } else if notificationStatus == .notDetermined {
                        Button {
                            Task {
                                _ = await ReminderScheduler.requestAuthorization()
                                await refresh()
                            }
                        } label: { Label("Cho phép nhắc nhở", systemImage: "bell.badge") }
                    } else {
                        Label("Nhắc nhở đang bật", systemImage: "bell.fill").foregroundStyle(.green)
                    }
                    Button {
                        Task { await ReminderScheduler.sendTest() }
                    } label: { Label("Gửi thử 1 thông báo (sau 5 giây)", systemImage: "paperplane") }
                }
            }
            .navigationTitle("Mục tiêu")
            .sheet(item: $editingSlot) { slot in SlotEditorView(slot: slot) }
            .sheet(isPresented: $showNewSlot) { SlotEditorView(slot: nil) }
            .task(id: scheduleSignature) { await refresh() }
        }
    }

    private var todayRing: some View {
        let progress = min(1, Double(todayMinutes) / Double(max(goalMinutes, 1)))
        return VStack(spacing: 10) {
            ZStack {
                Circle().stroke(AppTheme.accent.opacity(0.15), lineWidth: 16)
                Circle().trim(from: 0, to: progress)
                    .stroke(AppTheme.warmGradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: progress)
                VStack(spacing: 2) {
                    Text("\(todayMinutes)").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("/ \(goalMinutes) phút").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, height: 170)
            Text(progress >= 1 ? "Đã hoàn thành mục tiêu hôm nay 🎉" : "Còn \(max(0, goalMinutes - todayMinutes)) phút nữa là đạt mục tiêu")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func refresh() async {
        let infos = slots.filter(\.isEnabled).map {
            ReminderScheduler.SlotInfo(id: $0.id, hour: $0.hour, minute: $0.minute,
                                       durationMinutes: $0.durationMinutes, label: $0.label)
        }
        await ReminderScheduler.reschedule(slots: infos, goalMinutes: goalMinutes)
        notificationStatus = await ReminderScheduler.authorizationStatus()
    }
}

private struct SlotRow: View {
    @Bindable var slot: ReadingSlot
    var onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.timeText).font(.title3.weight(.semibold).monospacedDigit())
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Toggle("", isOn: $slot.isEnabled).labelsHidden()
        }
        .opacity(slot.isEnabled ? 1 : 0.5)
    }

    private var icon: String {
        switch slot.hour {
        case 5..<11: return "sunrise.fill"
        case 11..<14: return "sun.max.fill"
        case 14..<18: return "sun.haze.fill"
        default: return "moon.stars.fill"
        }
    }

    private var subtitle: String {
        let name = slot.label.isEmpty ? "" : "\(slot.label) · "
        return "\(name)\(slot.durationMinutes) phút · nhắc lúc \(reminderTime)"
    }

    private var reminderTime: String {
        var total = slot.hour * 60 + slot.minute - ReminderScheduler.minutesBefore
        if total < 0 { total += 1440 }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct SlotEditorView: View {
    let slot: ReadingSlot?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var time = Date()
    @State private var duration = 30
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Giờ bắt đầu", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                Stepper("Đọc trong \(duration) phút", value: $duration, in: 5...240, step: 5)
                TextField("Tên (vd: Trước khi ngủ)", text: $label)
                Section {
                    Text("Bạn sẽ nhận thông báo trước giờ này 10 phút.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(slot == nil ? "Khung giờ mới" : "Sửa khung giờ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save) }
            }
            .onAppear(perform: setup)
        }
        .presentationDetents([.large])
    }

    private func setup() {
        guard let slot else {
            time = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
            return
        }
        time = Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: Date()) ?? Date()
        duration = slot.durationMinutes
        label = slot.label
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = comps.hour ?? 21, minute = comps.minute ?? 0
        if let slot {
            slot.hour = hour
            slot.minute = minute
            slot.durationMinutes = duration
            slot.label = label
        } else {
            context.insert(ReadingSlot(hour: hour, minute: minute, durationMinutes: duration, label: label))
        }
        try? context.save()
        dismiss()
    }
}
