import Foundation

public enum Barcode {
    /// The key under which a scanned code is stored and looked up: 8 digits for EAN-8, 13 digits
    /// for EAN-13, and UPC-A as 13 digits with a leading zero. The same package then always
    /// gives the same key, whichever symbology the scanner reports. Nil when the code is not a
    /// valid EAN-8, EAN-13 or UPC-A, so a misread never reaches the database.
    public static func normalized(_ scanned: String) -> String? {
        let code = scanned.filter { !$0.isWhitespace }
        guard code.allSatisfy({ $0.isASCII && $0.isNumber }), hasValidCheckDigit(code) else { return nil }
        switch code.count {
        case 8, 13: return code
        case 12: return "0" + code
        default: return nil
        }
    }

    /// The GS1 check digit: from the right, the digits before the last weigh 3, 1, 3, 1, ...
    private static func hasValidCheckDigit(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == code.count, let check = digits.last else { return false }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { total, item in
            total + item.element * (item.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }
}
