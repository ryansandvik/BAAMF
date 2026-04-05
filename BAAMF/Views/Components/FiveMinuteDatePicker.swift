import SwiftUI
import UIKit

/// A Form-compatible date/time picker that restricts minute selection to 5-minute
/// intervals (0, 5, 10 … 55). Uses UIDatePicker under the hood because SwiftUI's
/// DatePicker has no equivalent API.
///
/// Usage mirrors SwiftUI's DatePicker:
/// ```swift
/// FiveMinuteDatePicker("Start", selection: $date)
/// FiveMinuteDatePicker("End",   selection: $date, displayedComponents: [.hourAndMinute])
/// ```
struct FiveMinuteDatePicker: View {

    let label: String
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents

    init(_ label: String,
         selection: Binding<Date>,
         displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.label = label
        self._selection = selection
        self.displayedComponents = displayedComponents
    }

    var body: some View {
        LabeledContent(label) {
            _UIDatePickerBridge(selection: $selection,
                                displayedComponents: displayedComponents)
                // Explicitly size the bridge so SwiftUI doesn't collapse the
                // UIViewRepresentable — compact UIDatePicker pills are 34pt tall.
                .frame(height: 34)
        }
        // Ensure the List row is tall enough to comfortably contain the pills.
        .frame(minHeight: 44)
    }
}

// MARK: - UIViewRepresentable bridge

private struct _UIDatePickerBridge: UIViewRepresentable {

    @Binding var selection: Date
    var displayedComponents: DatePickerComponents

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.minuteInterval = 5
        picker.preferredDatePickerStyle = .compact
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.dateChanged(_:)),
                         for: .valueChanged)
        // Prevent UIKit from compressing the picker below its natural height.
        picker.setContentHuggingPriority(.required, for: .vertical)
        picker.setContentCompressionResistancePriority(.required, for: .vertical)
        apply(components: displayedComponents, to: picker)
        picker.date = selection
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        apply(components: displayedComponents, to: uiView)
        // Only push a new date when it differs by more than a minute to avoid
        // feedback loops where our own binding write re-triggers the coordinator.
        if abs(uiView.date.timeIntervalSince(selection)) > 60 {
            uiView.date = selection
        }
    }

    private func apply(components: DatePickerComponents, to picker: UIDatePicker) {
        switch components {
        case [.date]:           picker.datePickerMode = .date
        case [.hourAndMinute]:  picker.datePickerMode = .time
        default:                picker.datePickerMode = .dateAndTime
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject {
        var parent: _UIDatePickerBridge
        init(_ p: _UIDatePickerBridge) { parent = p }

        @objc func dateChanged(_ sender: UIDatePicker) {
            // Programmatic date changes on UIDatePicker don't fire .valueChanged,
            // so this only executes on genuine user interaction — no binding loops.
            parent.selection = sender.date
        }
    }
}
