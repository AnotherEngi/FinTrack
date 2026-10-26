import Foundation

/// The prototype uses USD only. Currency expansion needs an explicit scale policy.
public enum Currency: String, Codable, Sendable, CaseIterable {
    case usd = "USD"
}

/// Positive amounts are outflows; negative amounts are inflows, including refunds.
/// The sign alone does not distinguish income, refunds, payments, or transfers.
public struct Money: Codable, Equatable, Sendable {
    public static let amountSignConvention = "outflow-positive-v1"

    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency = .usd) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Strict decimal input: a sign, digits, and at most two fractional digits.
    /// No Double conversion, implicit rounding, grouping, or currency conversion.
    public init(decimalText: String, currency: Currency = .usd) throws {
        var text = decimalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let negative = text.first == "-"
        if negative || text.first == "+" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              let whole = parts.first, !whole.isEmpty,
              whole.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw MoneyError.invalidAmount
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 2,
              fraction.utf8.allSatisfy({ (48...57).contains($0) }),
              parts.count == 1 || !fraction.isEmpty else {
            throw MoneyError.invalidAmount
        }
        let digits = (negative ? "-" : "") + String(whole) + fraction
            + String(repeating: "0", count: 2 - fraction.count)
        guard let value = Int64(digits) else { throw MoneyError.outOfRange }
        self.init(minorUnits: value, currency: currency)
    }

    public var decimalText: String {
        let magnitude = minorUnits.magnitude
        let cents = String(magnitude % 100)
        return (minorUnits < 0 ? "-" : "") + String(magnitude / 100)
            + "." + (cents.count == 1 ? "0" : "") + cents
    }

    public var decimalValue: Decimal { Decimal(minorUnits) / 100 }

    private enum CodingKeys: String, CodingKey { case minorUnits, currency }
    public init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        let text = try value.decode(String.self, forKey: .minorUnits)
        guard let cents = Int64(text), String(cents) == text else { throw MoneyError.invalidAmount }
        self.init(minorUnits: cents, currency: try value.decode(Currency.self, forKey: .currency))
    }
    public func encode(to encoder: any Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(String(minorUnits), forKey: .minorUnits); try value.encode(currency, forKey: .currency)
    }
}

public enum MoneyError: Error, Equatable, LocalizedError {
    case invalidAmount
    case outOfRange

    public var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter an amount such as 12.34, using a decimal point."
        case .outOfRange: "This amount is outside the supported range."
        }
    }
}
