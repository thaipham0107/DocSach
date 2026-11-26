import SwiftUI

struct ReaderSettingsSheet: View {
    @Binding var themeRaw: String
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var fontRaw: String
    @Binding var margin: Double
    @Binding var warmth: Double

    @State private var brightness = Double(UIScreen.main.brightness)

    var body: some View {
        NavigationStack {
            Form {
                Section("Màu nền") {
                    HStack(spacing: 14) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Button { themeRaw = theme.rawValue } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(theme.background)
                                        .overlay(Text("Aa").font(.headline).foregroundStyle(theme.text))
                                        .overlay(Circle().stroke(themeRaw == theme.rawValue ? AppTheme.accent : Color.gray.opacity(0.3),
                                                                 lineWidth: themeRaw == theme.rawValue ? 3 : 1))
                                        .frame(width: 54, height: 54)
                                    Text(theme.name).font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Ánh sáng") {
                    HStack {
                        Image(systemName: "sun.min")
                        Slider(value: $brightness, in: 0.02...1)
                            .onChange(of: brightness) { _, value in UIScreen.main.brightness = CGFloat(value) }
                        Image(systemName: "sun.max.fill")
                    }
                    HStack {
                        Image(systemName: "lightbulb")
                        Slider(value: $warmth, in: 0...1)
                        Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                    }
                    Text("Thanh dưới là “đèn vàng”: kéo sang phải để màn hình ấm hơn, dịu mắt khi đọc buổi tối.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Chữ") {
                    HStack {
                        Button { fontSize = max(12, fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                            .buttonStyle(.bordered)
                        Spacer()
                        Text("\(Int(fontSize)) pt").monospacedDigit()
                        Spacer()
                        Button { fontSize = min(36, fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                            .buttonStyle(.bordered)
                    }
                    Picker("Phông chữ", selection: $fontRaw) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.name).font(font.swiftUIFont).tag(font.rawValue)
                        }
                    }
                    Picker("Giãn dòng", selection: $lineHeight) {
                        Text("Hẹp").tag(1.35)
                        Text("Vừa").tag(1.6)
                        Text("Rộng").tag(1.9)
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading) {
                        Text("Lề trang: \(Int(margin))")
                        Slider(value: $margin, in: 8...48, step: 2)
                    }
                }
            }
            .navigationTitle("Giao diện đọc")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
