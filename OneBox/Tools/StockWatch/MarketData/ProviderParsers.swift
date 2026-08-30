import Foundation

enum EastMoneyParser {
    private static let providerTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    static func minuteBar(from raw: String) -> MinuteBar? {
        let values = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard values.count >= 5,
            let date = ProviderDateParser.minute(
                String(values[0]),
                timeZone: providerTimeZone
            ),
            let open = Double(values[1]),
            let close = Double(values[2]),
            let high = Double(values[3]),
            let low = Double(values[4]),
            [open, close, high, low].allSatisfy({ $0.isFinite && $0 > 0 })
        else { return nil }

        return MinuteBar(
            time: date,
            open: open,
            close: close,
            high: max(open, close, high, low),
            low: min(open, close, high, low)
        )
    }

    static func namespace(for item: EastMoneySearchItem) -> SymbolNamespace? {
        let classification = item.classification.lowercased()
        switch item.marketNumber {
        case "1":
            guard ["astock", "index", "fund"].contains(classification) else {
                return nil
            }
            return .shanghai
        case "0":
            if classification == "neeq" {
                return item.securityType == "27" ? .beijing : nil
            }
            guard ["astock", "index", "fund"].contains(classification) else {
                return nil
            }
            return .shenzhen
        case "116":
            return classification == "hk" ? .hongKong : nil
        case "105", "106", "107":
            return classification == "usstock" ? .unitedStates : nil
        default:
            return nil
        }
    }

    static func validatedQuoteIdentifier(
        for item: EastMoneySearchItem,
        instrument: Instrument
    ) -> String? {
        guard namespace(for: item) == instrument.namespace,
            let itemInstrument = try? Instrument(
                validatingSymbol: item.code,
                name: item.name,
                namespace: instrument.namespace
            ),
            itemInstrument.id == instrument.id,
            let delimiter = item.quoteIdentifier.firstIndex(of: ".")
        else { return nil }

        let marketNumber = item.quoteIdentifier[..<delimiter]
        let symbolStart = item.quoteIdentifier.index(after: delimiter)
        let symbol = String(item.quoteIdentifier[symbolStart...])
        guard marketNumber == item.marketNumber,
            !symbol.isEmpty,
            let quoteInstrument = try? Instrument(
                validatingSymbol: symbol,
                name: instrument.name,
                namespace: instrument.namespace
            ),
            quoteInstrument.symbol == symbol,
            quoteInstrument.id == instrument.id
        else { return nil }
        return item.quoteIdentifier
    }

    static func deterministicQuoteIdentifier(for instrument: Instrument) -> String? {
        switch instrument.namespace {
        case .shanghai:
            "1.\(instrument.symbol)"
        case .shenzhen, .beijing:
            "0.\(instrument.symbol)"
        case .hongKong:
            "116.\(instrument.symbol)"
        case .unitedStates:
            nil
        }
    }
}

enum TencentParser {
    static func code(for instrument: Instrument) -> String {
        switch instrument.namespace {
        case .shanghai:
            return "sh\(instrument.symbol)"
        case .shenzhen:
            return "sz\(instrument.symbol)"
        case .beijing:
            return "bj\(instrument.symbol)"
        case .hongKong:
            return "hk\(instrument.symbol)"
        case .unitedStates:
            return "us\(instrument.symbol)"
        }
    }

    static func sessionDate(
        minuteDate: String,
        quoteTimestamp: String,
        market: Market
    ) -> String? {
        ProviderDateParser.tencentSessionDate(
            minuteDate: minuteDate,
            quoteTimestamp: quoteTimestamp,
            timeZone: market.timeZone
        )
    }

    static func minuteBar(
        from raw: String,
        date: String,
        market: Market
    ) -> MinuteBar? {
        let values = raw.split(separator: " ", omittingEmptySubsequences: true)
        guard values.count >= 2,
            let price = Double(values[1]),
            price.isFinite,
            price > 0,
            let parsedDate = ProviderDateParser.tencentMinute(
                date: date,
                time: String(values[0]),
                timeZone: market.timeZone
            )
        else { return nil }

        return MinuteBar(
            time: parsedDate,
            open: price,
            close: price,
            high: price,
            low: price
        )
    }
}

private enum ProviderDateParser {
    static func minute(_ raw: String, timeZone: TimeZone) -> Date? {
        let digits = Array(raw.utf8.filter { (48...57).contains($0) })
        guard digits.count >= 12 else { return nil }
        return date(from: Array(digits.prefix(12)), timeZone: timeZone)
    }

    static func tencentSessionDate(
        minuteDate: String,
        quoteTimestamp: String,
        timeZone: TimeZone
    ) -> String? {
        if let digits = tencentDateDigits(minuteDate),
            date(from: digits, timeZone: timeZone) != nil
        {
            return String(decoding: digits, as: UTF8.self)
        }
        guard let digits = tencentTimestampDigits(quoteTimestamp),
            date(from: digits, timeZone: timeZone) != nil
        else { return nil }
        return String(decoding: digits.prefix(8), as: UTF8.self)
    }

    static func tencentMinute(
        date rawDate: String,
        time rawTime: String,
        timeZone: TimeZone
    ) -> Date? {
        guard let day = tencentDateDigits(rawDate) else { return nil }
        let time = Array(rawTime.utf8)
        guard time.count == 4, time.allSatisfy(isASCIIDigit) else { return nil }
        return date(from: day + time, timeZone: timeZone)
    }

    private static func tencentDateDigits(_ raw: String) -> [UInt8]? {
        let bytes = Array(raw.utf8)
        if bytes.count == 8, bytes.allSatisfy(isASCIIDigit) {
            return bytes
        }
        guard bytes.count == 10,
            bytes[4] == 45,
            bytes[7] == 45
        else { return nil }
        var digits = Array(bytes[0..<4])
        digits.append(contentsOf: bytes[5..<7])
        digits.append(contentsOf: bytes[8..<10])
        return digits.allSatisfy(isASCIIDigit) ? digits : nil
    }

    private static func tencentTimestampDigits(_ raw: String) -> [UInt8]? {
        let bytes = Array(raw.utf8)
        if bytes.count == 14, bytes.allSatisfy(isASCIIDigit) {
            return bytes
        }
        guard bytes.count == 19,
            bytes[4] == 45,
            bytes[7] == 45,
            bytes[10] == 32 || bytes[10] == 84,
            bytes[13] == 58,
            bytes[16] == 58
        else { return nil }
        var digits = Array(bytes[0..<4])
        digits.append(contentsOf: bytes[5..<7])
        digits.append(contentsOf: bytes[8..<10])
        digits.append(contentsOf: bytes[11..<13])
        digits.append(contentsOf: bytes[14..<16])
        digits.append(contentsOf: bytes[17..<19])
        return digits.allSatisfy(isASCIIDigit) ? digits : nil
    }

    private static func date(from digits: [UInt8], timeZone: TimeZone) -> Date? {
        guard [8, 12, 14].contains(digits.count),
            let year = number(digits[0..<4]),
            let month = number(digits[4..<6]),
            let day = number(digits[6..<8]),
            let hour = digits.count >= 12 ? number(digits[8..<10]) : 0,
            let minute = digits.count >= 12 ? number(digits[10..<12]) : 0,
            let second = digits.count == 14 ? number(digits[12..<14]) : 0
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let parsedDate = calendar.date(
                from: DateComponents(
                    timeZone: timeZone,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute,
                    second: second
                )
            )
        else { return nil }
        let parsed = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: parsedDate
        )
        guard parsed.year == year,
            parsed.month == month,
            parsed.day == day,
            parsed.hour == hour,
            parsed.minute == minute,
            parsed.second == second
        else { return nil }
        return parsedDate
    }

    private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
        guard digits.allSatisfy(isASCIIDigit) else { return nil }
        return digits.reduce(0) { $0 * 10 + Int($1 - 48) }
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
    }
}
