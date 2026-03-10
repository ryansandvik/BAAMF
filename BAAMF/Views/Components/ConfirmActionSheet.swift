import SwiftUI

// MARK: - Confirm Action Sheet

/// A custom bottom sheet that replaces SwiftUI's `confirmationDialog`.
///
/// Unlike the system action sheet, this component has full-width layout,
/// scalable typography, and consistent appearance on all device sizes.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showDelete) {
///     ConfirmActionSheet(title: "Delete?", message: "This cannot be undone.") {
///         SheetActionButton(label: "Delete", role: .destructive) { deleteItem() }
///         Divider()
///         SheetActionButton(label: "Cancel", role: .cancel) { showDelete = false }
///     }
/// }
/// ```
struct ConfirmActionSheet<Actions: View>: View {

    let title: String
    let message: String?
    let actions: () -> Actions

    @State private var sheetHeight: CGFloat = 0

    init(title: String, message: String? = nil,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // Action buttons — callers place `Divider()` between each button
            actions()
        }
        // Auto-size the sheet to exactly fit its content
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ConfirmSheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ConfirmSheetHeightKey.self) { sheetHeight = $0 }
        .presentationDetents(sheetHeight > 0 ? [.height(sheetHeight)] : [.fraction(0.45)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Sheet action button

/// A full-width button styled for use inside `ConfirmActionSheet`.
/// Place a `Divider()` between adjacent buttons.
struct SheetActionButton: View {

    let label: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(label)
                .font(.body.weight(role == .destructive ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .foregroundStyle(labelColor)
        .buttonStyle(.plain)
    }

    private var labelColor: Color {
        switch role {
        case .destructive: return .red
        case .cancel:      return Color(.systemGray)
        default:           return .accentColor
        }
    }
}

// MARK: - Preference key

private struct ConfirmSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
