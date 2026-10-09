import Foundation

/// Money is stored as whole cents and shown in the device's currency.
nonisolated enum Money {
    static func currencyCode(locale: Locale = .current) -> String {
        locale.currency?.identifier ?? "EUR"
    }

    /// "€349" for whole amounts, "€349.90" otherwise.
    static func format(cents: Int, locale: Locale = .current) -> String {
        let digits = cents % 100 == 0 ? 0 : 2
        return (Decimal(cents) / 100).formatted(
            .currency(code: currencyCode(locale: locale))
                .precision(.fractionLength(digits))
                .locale(locale)
        )
    }

    /// Always two decimals, e.g. a cost per wear of "€0.85".
    static func format(fractionalCents cents: Double, locale: Locale = .current) -> String {
        (cents / 100).formatted(
            .currency(code: currencyCode(locale: locale))
                .precision(.fractionLength(2))
                .locale(locale)
        )
    }

    /// Parses what the user typed into a price field. Accepts "349", "349.90",
    /// "349,90", "1 299" and "1,299.50". A separator followed by one or two
    /// digits at the end is the decimal separator; any other separator is
    /// grouping. Returns nil when there are no digits.
    static func parseCents(_ text: String) -> Int? {
        let kept = text.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }
        guard kept.contains(where: \.isNumber) else { return nil }

        var whole = kept
        var fraction = ""
        if let last = kept.lastIndex(where: { $0 == "." || $0 == "," }) {
            let after = kept[kept.index(after: last)...]
            if (1...2).contains(after.count) {
                whole = String(kept[..<last])
                fraction = String(after)
            }
        }
        let wholeDigits = whole.filter(\.isNumber)
        guard let units = Int(wholeDigits.isEmpty ? "0" : wholeDigits) else { return nil }
        let cents = fraction.isEmpty ? 0 : Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        return units * 100 + cents
    }

    /// The value to prefill a price field with, e.g. "349" or "349.90".
    static func inputText(cents: Int, locale: Locale = .current) -> String {
        let value = Decimal(cents) / 100
        let digits = cents % 100 == 0 ? 0 : 2
        return value.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale))
    }
}

/// Temperatures are stored in °C and shown in °F where the region uses it.
nonisolated enum Temperature {
    static func usesFahrenheit(locale: Locale = .current) -> Bool {
        locale.measurementSystem == .us
    }

    /// "−20°C" or "−4°F", with a real minus sign.
    static func format(celsius: Double, locale: Locale = .current) -> String {
        let fahrenheit = usesFahrenheit(locale: locale)
        let value = Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded())
        let number = value < 0 ? "\u{2212}\(abs(value))" : "\(value)"
        return number + (fahrenheit ? "°F" : "°C")
    }

    static func format(celsius: Int, locale: Locale = .current) -> String {
        format(celsius: Double(celsius), locale: locale)
    }
}
