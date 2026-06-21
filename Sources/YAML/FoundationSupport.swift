// Foundation conveniences — Date/Data strategies and a Data input overload —
// gated so the codec core stays Foundation-free (Yams#358). FoundationEssentials
// is preferred; full Foundation is the fallback. ISO-8601 is implemented here
// with plain arithmetic (Howard Hinnant's civil-date algorithm) rather than
// `ISO8601DateFormatter` (locale/ICU, not in Essentials), so it needs no
// platform floor and no `@available` gate.

#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif

#if canImport(FoundationEssentials) || canImport(Foundation)

// MARK: - Strategies

extension YAMLEncoder {
    /// `Date` encoding, mirroring `JSONEncoder.DateEncodingStrategy`. Default
    /// `.iso8601` (YAML reads more naturally with text dates than the raw
    /// reference-date double that `.deferredToDate` produces).
    public enum DateEncodingStrategy: Sendable {
        /// Defer to `Date`'s own `Encodable` conformance, which emits its
        /// `timeIntervalSinceReferenceDate` as a `Double`.
        case deferredToDate

        /// Emit the number of seconds since 1 January 1970 (a `Double`).
        case secondsSince1970

        /// Emit the number of milliseconds since 1 January 1970 (a `Double`).
        case millisecondsSince1970

        /// Emit an ISO-8601 string in UTC, such as `2026-06-18T12:00:00Z`.
        ///
        /// The default. Text dates read more naturally in YAML than the raw
        /// reference-date double ``deferredToDate`` produces, and the
        /// conversion is computed with plain arithmetic so it needs no platform
        /// floor.
        case iso8601

        /// Emit the date using a caller-supplied closure.
        ///
        /// The closure receives the `Date` and an `Encoder` positioned at the
        /// current location; whatever it encodes becomes the value. It must be
        /// `@Sendable`.
        case custom(@Sendable (Date, any Encoder) throws -> Void)
    }

    /// `Data` encoding, mirroring `JSONEncoder.DataEncodingStrategy`.
    public enum DataEncodingStrategy: Sendable {
        /// Defer to `Data`'s own `Encodable` conformance, which emits a
        /// sequence of byte values.
        case deferredToData

        /// Emit a Base64-encoded string. This is the default.
        case base64

        /// Emit the data using a caller-supplied closure.
        ///
        /// The closure receives the `Data` and an `Encoder` positioned at the
        /// current location; whatever it encodes becomes the value. It must be
        /// `@Sendable`.
        case custom(@Sendable (Data, any Encoder) throws -> Void)
    }
}

extension YAMLDecoder {
    /// `Date` decoding, mirroring `JSONDecoder.DateDecodingStrategy`.
    public enum DateDecodingStrategy: Sendable {
        /// Defer to `Date`'s own `Decodable` conformance, reading a `Double`
        /// `timeIntervalSinceReferenceDate`.
        case deferredToDate

        /// Read a `Double` count of seconds since 1 January 1970.
        case secondsSince1970

        /// Read a `Double` count of milliseconds since 1 January 1970.
        case millisecondsSince1970

        /// Read an ISO-8601 string. The default.
        ///
        /// Accepts a `T` or space date/time separator, an optional fractional
        /// second, and a `Z` or `±HH:MM` zone offset; a string that isn't a
        /// valid ISO-8601 date throws `DecodingError.dataCorrupted`.
        case iso8601

        /// Read the date using a caller-supplied closure.
        ///
        /// The closure receives a `Decoder` positioned at the value and returns
        /// the decoded `Date`. It must be `@Sendable`.
        case custom(@Sendable (any Decoder) throws -> Date)
    }

    /// `Data` decoding, mirroring `JSONDecoder.DataDecodingStrategy`.
    public enum DataDecodingStrategy: Sendable {
        /// Defer to `Data`'s own `Decodable` conformance, reading a sequence of
        /// byte values.
        case deferredToData

        /// Read a Base64-encoded string. This is the default; an invalid
        /// Base64 string throws `DecodingError.dataCorrupted`.
        case base64

        /// Read the data using a caller-supplied closure.
        ///
        /// The closure receives a `Decoder` positioned at the value and returns
        /// the decoded `Data`. It must be `@Sendable`.
        case custom(@Sendable (any Decoder) throws -> Data)
    }

    /// Decodes a value of `type` from UTF-8 encoded YAML `Data`.
    ///
    /// A Foundation convenience that decodes the bytes as UTF-8 and forwards to
    /// the `String` overload of `decode(_:from:)`, so the same strategies,
    /// limits, and errors apply.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The UTF-8 encoded YAML document.
    /// - Returns: The decoded value.
    /// - Throws: The same errors as the `String` overload — `DecodingError`,
    ///   including `dataCorrupted` wrapping a ``YAMLError`` for malformed or
    ///   over-budget input.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decode(type, from: String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Encoder boxing

extension _YAMLEncoder {
    func boxFoundation(_ value: Encodable) throws -> YAMLValue? {
        if let date = value as? Date { return try boxDate(date) }
        if let data = value as? Data { return try boxData(data) }
        return nil
    }

    private func boxDate(_ date: Date) throws -> YAMLValue {
        switch options.dateStrategy {
        case .deferredToDate:
            return try boxViaEncodable(date)
        case .secondsSince1970:
            return .double(date.timeIntervalSince1970)
        case .millisecondsSince1970:
            return .double(date.timeIntervalSince1970 * 1000)
        case .iso8601:
            return .string(ISO8601.string(from: date))
        case .custom(let closure):
            return try boxViaClosure { try closure(date, $0) }
        }
    }

    private func boxData(_ data: Data) throws -> YAMLValue {
        switch options.dataStrategy {
        case .deferredToData:
            return try boxViaEncodable(data)
        case .base64:
            return .string(data.base64EncodedString())
        case .custom(let closure):
            return try boxViaClosure { try closure(data, $0) }
        }
    }

    /// Runs a strategy closure against this encoder and pops whatever it
    /// produced, unwinding the storage stack if it throws (the same discipline
    /// as `boxViaEncodable`).
    private func boxViaClosure(_ body: (any Encoder) throws -> Void) throws -> YAMLValue {
        let depth = storage.count
        do {
            try body(self)
        } catch {
            if storage.count > depth { _ = storage.popContainer() }
            throw error
        }
        guard storage.count > depth else { return .mapping(YAMLMapping()) }
        return storage.popContainer().resolved
    }
}

// MARK: - Decoder unboxing

extension _YAMLDecoder {
    func unboxFoundation<T: Decodable>(_ value: YAMLValue, as type: T.Type, at path: [any CodingKey]) throws -> T? {
        if type == Date.self {
            return (try unboxDate(value, at: path) as! T)
        }
        if type == Data.self {
            return (try unboxData(value, at: path) as! T)
        }
        return nil
    }

    private func unboxDate(_ value: YAMLValue, at path: [any CodingKey]) throws -> Date {
        switch options.dateStrategy {
        case .deferredToDate:
            return try Date(from: _YAMLDecoder(value: value, options: options, codingPath: path))
        case .secondsSince1970:
            return Date(timeIntervalSince1970: try unboxDouble(value, at: path))
        case .millisecondsSince1970:
            return Date(timeIntervalSince1970: try unboxDouble(value, at: path) / 1000)
        case .iso8601:
            let text = try unboxString(value, at: path)
            guard let date = ISO8601.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: path, debugDescription: "Expected an ISO-8601 date but found \"\(text)\"."))
            }
            return date
        case .custom(let closure):
            return try closure(_YAMLDecoder(value: value, options: options, codingPath: path))
        }
    }

    private func unboxData(_ value: YAMLValue, at path: [any CodingKey]) throws -> Data {
        switch options.dataStrategy {
        case .deferredToData:
            return try Data(from: _YAMLDecoder(value: value, options: options, codingPath: path))
        case .base64:
            let text = try unboxString(value, at: path)
            guard let data = Data(base64Encoded: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: path, debugDescription: "Expected base64-encoded Data but found an invalid string."))
            }
            return data
        case .custom(let closure):
            return try closure(_YAMLDecoder(value: value, options: options, codingPath: path))
        }
    }
}

// MARK: - ISO-8601 (UTC), arithmetic-only

enum ISO8601 {
    static func string(from date: Date) -> String {
        let dayLength = 86_400.0
        let interval = date.timeIntervalSince1970
        let dayIndex = (interval / dayLength).rounded(.down)
        let days = Int(dayIndex)
        let secondsInDay = Int((interval - dayIndex * dayLength).rounded(.down))

        let (year, month, day) = civilFromDays(days)
        let hour = secondsInDay / 3600
        let minute = (secondsInDay % 3600) / 60
        let second = secondsInDay % 60

        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2))Z"
    }

    static func date(from text: String) -> Date? {
        // Expected: YYYY-MM-DD ('T'|' ') HH:MM:SS[.fraction][Z | ±HH:MM]
        let scalars = Array(text)
        guard let tIndex = scalars.firstIndex(where: { $0 == "T" || $0 == "t" || $0 == " " }) else { return nil }
        let datePart = String(scalars[..<tIndex])
        var timePart = String(scalars[(tIndex + 1)...])

        let dateFields = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard dateFields.count == 3,
              let year = Int(dateFields[0]),
              let month = Int(dateFields[1]),
              let day = Int(dateFields[2]) else { return nil }

        // Timezone suffix.
        var offsetSeconds = 0
        if timePart.hasSuffix("Z") || timePart.hasSuffix("z") {
            timePart.removeLast()
        } else if let sign = timePart.last(where: { $0 == "+" || $0 == "-" }),
                  let signIndex = timePart.lastIndex(of: sign),
                  signIndex > timePart.startIndex,
                  timePart[timePart.index(before: signIndex)] == ":" || timePart.distance(from: timePart.startIndex, to: signIndex) >= 6 {
            let offsetText = String(timePart[signIndex...])
            timePart = String(timePart[..<signIndex])
            guard let parsed = parseOffset(offsetText) else { return nil }
            offsetSeconds = parsed
        }

        var fraction = 0.0
        if let dot = timePart.firstIndex(of: ".") {
            let fractionText = "0" + String(timePart[dot...])
            fraction = Double(fractionText) ?? 0
            timePart = String(timePart[..<dot])
        }

        let timeFields = timePart.split(separator: ":", omittingEmptySubsequences: false)
        guard timeFields.count >= 2,
              let hour = Int(timeFields[0]),
              let minute = Int(timeFields[1]) else { return nil }
        let second = timeFields.count >= 3 ? (Int(timeFields[2]) ?? 0) : 0

        let days = daysFromCivil(year: year, month: month, day: day)
        let epoch = Double(days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds) + fraction
        return Date(timeIntervalSince1970: epoch)
    }

    private static func parseOffset(_ text: String) -> Int? {
        // ±HH:MM or ±HHMM
        guard let first = text.first, first == "+" || first == "-" else { return nil }
        let sign = first == "-" ? -1 : 1
        let digits = text.dropFirst().filter { $0 != ":" }
        guard digits.count == 4,
              let hours = Int(digits.prefix(2)),
              let minutes = Int(digits.suffix(2)) else { return nil }
        return sign * (hours * 3600 + minutes * 60)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let negative = value < 0
        let digits = String(abs(value))
        let padded = digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
        return negative ? "-" + padded : padded
    }

    /// Days since 1970-01-01 → (year, month, day). Howard Hinnant, public domain.
    private static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// (year, month, day) → days since 1970-01-01. Howard Hinnant, public domain.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

#endif
