import Foundation

/// A calendar date, encoded as YYYY-MM-DD without a timezone or time of day.
public struct TransactionDate: Codable, Hashable, Comparable, Sendable {
    public let iso8601: String

    public init(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)), (1...9999).contains(year),
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)) else { throw LedgerError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            throw LedgerError.invalidDate
        }
        iso8601 = value
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.iso8601 < rhs.iso8601 }
}
