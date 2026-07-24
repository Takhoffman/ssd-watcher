import SwiftUI

enum DesignSystem {
    enum Colors {
        static let healthy = Color(red: 0.12, green: 0.68, blue: 0.48)
        static let elevated = Color(red: 0.95, green: 0.61, blue: 0.12)
        static let critical = Color(red: 0.91, green: 0.25, blue: 0.27)
        static let accent = Color(red: 0.25, green: 0.48, blue: 0.96)
        static let cardBorder = Color.primary.opacity(0.08)
    }

    enum Spacing {
        static let compact: CGFloat = 6
        static let standard: CGFloat = 12
        static let roomy: CGFloat = 18
        static let section: CGFloat = 22
    }

    static let cornerRadius: CGFloat = 14
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous)
                    .fill(.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }
}

enum Formatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func byteCount(_ value: Int64) -> String {
        bytes.string(fromByteCount: value)
    }

    static func recordRate(_ value: Double) -> String {
        if value < 0.05 { return "Idle" }
        if value < 10 { return String(format: "%.1f records/s", value) }
        return String(format: "%.0f records/s", value)
    }

    static func byteRate(_ value: Double) -> String {
        if value < 1 { return "Idle" }
        return "\(bytes.string(fromByteCount: Int64(value)))/s"
    }
}
