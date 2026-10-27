/// `#RRGGBB` 形式の色。16 進の大文字小文字は区別せず、`hexString` は大文字に正規化する。
public struct CalendarColor: Sendable, Hashable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: String) throws {
        let digits = Array(hex.utf8)
        guard digits.count == 7, digits[0] == UInt8(ascii: "#") else {
            throw DomainError.invalidColor(hex)
        }
        var values: [UInt8] = []
        for digit in digits.dropFirst() {
            guard let value = Self.hexValue(digit) else { throw DomainError.invalidColor(hex) }
            values.append(value)
        }
        self.init(
            red: values[0] << 4 | values[1],
            green: values[2] << 4 | values[3],
            blue: values[4] << 4 | values[5]
        )
    }

    public var hexString: String {
        let digits = Array("0123456789ABCDEF")
        return "#" + [red, green, blue].map { byte in
            String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
        }.joined()
    }

    private static func hexValue(_ ascii: UInt8) -> UInt8? {
        switch ascii {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): ascii - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): ascii - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): ascii - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
