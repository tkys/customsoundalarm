import SwiftUI
import UIKit

/// 時刻ホイール（#149）。
///
/// SwiftUI の `DatePicker` はアラビア語などの RTL 環境で「分 → 時」の順に
/// 鏡像表示される。時刻は言語によらず「時 → 分」で読むため、
/// `UIDatePicker` を `semanticContentAttribute = .forceLeftToRight` で包み、
/// ホイールだけは左から右の並びを保つ。
/// （`.environment(\.layoutDirection, .leftToRight)` は UIDatePicker 内部の
/// ホイールには効かないため、UIKit 側で固定する）
struct TimeWheelPicker: UIViewRepresentable {

    @Binding var date: Date

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.semanticContentAttribute = .forceLeftToRight
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.dateChanged(_:)),
            for: .valueChanged
        )
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.date != date {
            picker.date = date
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TimeWheelPicker

        init(_ parent: TimeWheelPicker) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: UIDatePicker) {
            // UIDatePicker の valueChanged はメインスレッドで来る。
            parent.date = sender.date
        }
    }
}
