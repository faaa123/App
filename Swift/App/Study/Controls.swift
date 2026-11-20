import StudyCore
import SwiftUI
import UIKit

/// A 24-hour time picker bound to a logical-day offset. As an end time, 4:00
/// means the end of the day (1440).
struct OffsetPicker: View {
    let label: String
    @Binding var offset: Int
    let isEnd: Bool

    var body: some View {
        DatePicker(label, selection: dateBinding, displayedComponents: .hourAndMinute)
            .environment(\.locale, Locale(identifier: "ja_JP"))
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                let (h, m) = LogicalDay.clockParts(offset)
                return Self.calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: h, minute: m)) ?? Date()
            },
            set: { d in
                let c = Self.calendar.dateComponents([.hour, .minute], from: d)
                let h = c.hour ?? 0, m = c.minute ?? 0
                offset = isEnd ? LogicalDay.toEndOffset(h, m) : LogicalDay.toOffset(h, m)
            }
        )
    }

    private static let calendar = Calendar(identifier: .gregorian)
}

/// −/+ minutes.
struct MinuteStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 5

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            LabeledContent(label) {
                Text(Format.minutes(value)).monospacedDigit()
            }
        }
        .accessibilityValue(Format.minutes(value))
    }
}

/// A short confirmation at the bottom of the screen, optionally with an
/// action (取り消す). It is a transient control, so it floats on Liquid
/// Glass. It does not time out while VoiceOver is running (HIG: avoid
/// time-limited UI).
struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    var actionLabel: String?
    var action: (() -> Void)?
}

private struct ToastOverlay: ViewModifier {
    @Binding var toast: ToastMessage?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = toast {
                HStack(spacing: 16) {
                    Text(t.text)
                        .lineLimit(3)
                        .frame(maxWidth: 420, alignment: .leading)
                    if let label = t.actionLabel, let action = t.action {
                        Button(label) {
                            toast = nil
                            action()
                        }
                        .buttonStyle(.glassProminent)
                    }
                    Button("閉じる", systemImage: "xmark") { toast = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t.id) {
                    UIAccessibility.post(notification: .announcement, argument: t.text)
                    guard !voiceOver else { return }
                    try? await Task.sleep(for: .seconds(t.action == nil ? 4 : 8))
                    if toast?.id == t.id { toast = nil }
                }
            }
        }
        .animation(.snappy, value: toast?.id)
    }
}

extension View {
    func toast(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastOverlay(toast: toast))
    }
}

/// Explains why no chime will sound, with a way to fix it.
struct ChimePermissionNotice: View {
    @Environment(NotificationChimeScheduler.self) private var chimes

    var body: some View {
        if chimes.permission == .denied {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("通知がオフのため、チャイムは鳴りません")
                        .font(.subheadline.weight(.semibold))
                    Button("設定で通知をオンにする") { chimes.openSettings() }
                        .font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
