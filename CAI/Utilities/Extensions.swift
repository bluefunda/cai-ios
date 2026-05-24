import Foundation
import SwiftUI

// MARK: - Date Formatting

extension Date {
    static func fromISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - String

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func truncated(to length: Int, trailing: String = "…") -> String {
        guard count > length else { return self }
        return String(prefix(length)) + trailing
    }
}

// MARK: - Color

extension Color {
    static let brandBlue = Color(red: 0.118, green: 0.392, blue: 0.906)   // #1e64e7
    static let brandNavy = Color(red: 0.106, green: 0.118, blue: 0.216)   // #1b1e37
}

// MARK: - View Helpers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Task Retry

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - URL Helpers

extension URL {
    static func safe(_ string: String) -> URL? {
        URL(string: string)
    }
}
