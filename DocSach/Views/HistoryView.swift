import SwiftUI
import SwiftData

/// Lịch sử đọc theo lịch: mỗi ngày tô màu theo % mục tiêu, chạm vào ngày để xem chi tiết.
struct HistoryView: View {
    @Query private var days: [ReadingDay]
    @Query(sort: \ReadingSession.startedAt, order: .reverse) private var sessions: [ReadingSession]
    @AppStorage(ReadingStats.goalKey) private var goalMinutes = ReadingStats.defaultGoal

    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedKey = ReadingStats.key(for: Date())

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // Thứ Hai đầu tuần
        c.timeZone = .current
        return c
    }

    private var dayMap: [String: ReadingDay] {
        Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func goal(for key: String) -> Int {
        dayMap[key]?.goalMinutes ?? goalMinutes
    }

    private func minutes(for key: String) -> Int {
        dayMap[key]?.minutes ?? 0
    }

    /// Các ô của tháng (nil = ô trống đầu tháng).
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            result.append(calendar.date(byAdding: .day, value: d - 1, to: month))
        }
        return result
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "'Tháng' M, yyyy"
        return f.string(from: month)
    }

    private var monthKeys: [String] {
        cells.compactMap { $0 }.filter { $0 <= Date() }.map { ReadingStats.key(for: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                totalsCard
                calendarCard
                dayDetail
            }
            .padding()
        }
        .background(AppTheme.paper.ignoresSafeArea())
        .navigationTitle("Lịch sử đọc")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Tổng quan

    private var totalsCard: some View {
        let allMinutes = days.reduce(0) { $0 + $1.minutes }
        let monthMinutes = monthKeys.reduce(0) { $0 + minutes(for: $1) }
        let monthGoal = monthKeys.reduce(0) { $0 + goal(for: $1) }
        let metDays = monthKeys.filter { minutes(for: $0) >= goal(for: $0) }.count
        let readDays = monthKeys.filter { minutes(for: $0) > 0 }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Tổng thời gian đã đọc").font(.subheadline).opacity(0.9)
            Text(ReadingStats.durationText(minutes: allMinutes)).font(.system(size: 32, weight: .bold, design: .rounded))
            Divider().overlay(Color.white.opacity(0.5))
            HStack(alignment: .top) {
                stat(title: "Tháng này", value: "\(monthMinutes)/\(monthGoal) phút")
                Spacer()
                stat(title: "Ngày đạt mục tiêu", value: "\(metDays)/\(monthKeys.count)")
                Spacer()
                stat(title: "TB ngày có đọc", value: readDays == 0 ? "0 phút" : "\(monthMinutes / readDays) phút")
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.warmGradient, in: RoundedRectangle(cornerRadius: 18))
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).opacity(0.85)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    // MARK: Lịch

    private var calendarCard: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(month, equalTo: Date(), toGranularity: .month))
            }
            .padding(.horizontal, 4)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["T2", "T3", "T4", "T5", "T6", "T7", "CN"], id: \.self) { d in
                    Text(d).font(.caption2.bold()).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 44) }
                }
            }

            HStack(spacing: 14) {
                legend(color: .green, text: "Đạt mục tiêu")
                legend(color: AppTheme.accent, text: "Có đọc")
                legend(color: Color.gray.opacity(0.25), text: "Chưa đọc")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func dayCell(_ date: Date) -> some View {
        let key = ReadingStats.key(for: date)
        let mins = minutes(for: key)
        let g = max(goal(for: key), 1)
        let ratio = min(1, Double(mins) / Double(g))
        let isFuture = date > Date()
        let isSelected = key == selectedKey
        let isToday = calendar.isDateInToday(date)
        let fill: Color = mins >= g ? .green : (mins > 0 ? AppTheme.accent.opacity(0.25 + 0.6 * ratio) : Color.gray.opacity(0.12))

        return Button { selectedKey = key } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                if mins > 0 {
                    Text("\(mins)'").font(.system(size: 9, weight: .semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(mins >= g || ratio > 0.5 ? Color.white : AppTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(isFuture ? Color.clear : fill))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? AppTheme.ink : (isToday ? AppTheme.accent : .clear), lineWidth: isSelected ? 2 : 1))
            .opacity(isFuture ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let m = calendar.date(byAdding: .month, value: delta, to: month) { month = m }
    }

    // MARK: Chi tiết ngày

    private var dayDetail: some View {
        let mins = minutes(for: selectedKey)
        let g = goal(for: selectedKey)
        let daySessions = sessions.filter { $0.day == selectedKey }
        let date = ReadingStats.date(from: selectedKey) ?? Date()
        let f: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.dateFormat = "EEEE, dd/MM/yyyy"
            return f
        }()

        return VStack(alignment: .leading, spacing: 12) {
            Text(f.string(from: date).capitalized).font(.headline)
            HStack {
                ProgressView(value: min(1, Double(mins) / Double(max(g, 1))))
                    .tint(mins >= g ? .green : AppTheme.accent)
                Text("\(mins)/\(g) phút").font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Text(mins >= g ? "Đã đạt mục tiêu ✅" : (mins == 0 ? "Ngày này chưa đọc." : "Còn thiếu \(g - mins) phút so với mục tiêu."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !daySessions.isEmpty {
                Divider()
                ForEach(daySessions) { s in
                    HStack {
                        Image(systemName: "book.fill").foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.bookTitle).font(.subheadline).lineLimit(1)
                            Text(s.startedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(max(1, Int(s.seconds / 60))) phút").font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }
}
