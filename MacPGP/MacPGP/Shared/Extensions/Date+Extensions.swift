import Foundation

extension Date {
    var isExpired: Bool {
        self < Date()
    }

    var isPastDate: Bool {
        self < Date()
    }

    var isFutureDate: Bool {
        self > Date()
    }

    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    func adding(years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: years, to: self) ?? self
    }

    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortFormatted: String {
        formatted(date: .abbreviated, time: .omitted)
    }

    var longFormatted: String {
        formatted(date: .long, time: .shortened)
    }
}
