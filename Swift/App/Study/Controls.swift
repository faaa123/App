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

/// −/+ minutes in steps of 5.
struct MinuteStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 5

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            LabeledContent(label, value: "\(value)分")
        }
        .accessibilityValue("\(value)分")
    }
}

/// A short message at the bottom, optionally with an action (元に戻す).
struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    var actionLabel: String?
    var action: (() -> Void)?
}

private struct ToastOverlay: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = toast {
                HStack(spacing: 16) {
                    Text(t.text).lineLimit(3)
                    if let label = t.actionLabel, let action = t.action {
                        Button(label) {
                            toast = nil
                            action()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(t.id)
                .task(id: t.id) {
                    try? await Task.sleep(for: .seconds(t.action == nil ? 4 : 6))
                    if toast?.id == t.id { toast = nil }
                }
                .onAppear {
                    UIAccessibility.post(notification: .announcement, argument: t.text)
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
