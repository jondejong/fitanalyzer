import Foundation

/// A single decoded value from a FIT message field.
enum FitValue: Sendable {
    case int(Int64)
    case double(Double)
    case string(String)

    var number: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .string: return nil
        }
    }
}

/// One data message: a global message number plus its fields keyed by field number.
struct FitMessage: Sendable {
    let globalNumber: UInt16
    var fields: [UInt8: FitValue]

    func number(_ field: UInt8) -> Double? { fields[field]?.number }
}

enum FitError: LocalizedError {
    case notAFitFile
    case noData

    var errorDescription: String? {
        switch self {
        case .notAFitFile: return "This doesn't look like a FIT file."
        case .noData: return "The file contains no activity data."
        }
    }
}

/// Decoder for the Garmin/ANT+ FIT binary format.
///
/// Handles normal and compressed-timestamp record headers, both byte orders,
/// developer fields (skipped) and chained files. Truncated files yield whatever
/// could be read before the cut-off.
enum FitDecoder {
    private struct FieldDef {
        let number: UInt8
        let size: Int
        let baseType: UInt8
    }

    private struct MessageDef {
        let globalNumber: UInt16
        let bigEndian: Bool
        let fields: [FieldDef]
        let developerBytes: Int
        var dataSize: Int { fields.reduce(0) { $0 + $1.size } + developerBytes }
    }

    static func decode(_ data: Data) throws -> [FitMessage] {
        let bytes = [UInt8](data)
        var messages: [FitMessage] = []
        var pos = 0

        while bytes.count - pos >= 12 {
            let headerSize = Int(bytes[pos])
            guard headerSize >= 12, pos + headerSize <= bytes.count,
                  bytes[pos + 8] == 0x2E, bytes[pos + 9] == 0x46,   // ".F"
                  bytes[pos + 10] == 0x49, bytes[pos + 11] == 0x54  // "IT"
            else { break }
            let dataSize = Int(bytes[pos + 4]) | Int(bytes[pos + 5]) << 8
                | Int(bytes[pos + 6]) << 16 | Int(bytes[pos + 7]) << 24
            let start = pos + headerSize
            let end = min(start + dataSize, bytes.count)
            decodeRecords(bytes, from: start, to: end, into: &messages)
            pos = start + dataSize + 2 // skip trailing CRC
        }

        if pos == 0 { throw FitError.notAFitFile }
        return messages
    }

    private static func decodeRecords(_ b: [UInt8], from start: Int, to end: Int, into messages: inout [FitMessage]) {
        var defs = [MessageDef?](repeating: nil, count: 16)
        var lastTimestamp: Int64 = 0
        var pos = start

        while pos < end {
            let header = b[pos]
            pos += 1

            if header & 0x80 == 0, header & 0x40 != 0 {
                // Definition message
                let local = Int(header & 0x0F)
                guard pos + 5 <= end else { return }
                let big = b[pos + 1] == 1
                let global = big
                    ? UInt16(b[pos + 2]) << 8 | UInt16(b[pos + 3])
                    : UInt16(b[pos + 3]) << 8 | UInt16(b[pos + 2])
                let count = Int(b[pos + 4])
                pos += 5
                guard pos + count * 3 <= end else { return }
                var fields: [FieldDef] = []
                fields.reserveCapacity(count)
                for i in 0..<count {
                    let o = pos + i * 3
                    fields.append(FieldDef(number: b[o], size: Int(b[o + 1]), baseType: b[o + 2]))
                }
                pos += count * 3
                var devBytes = 0
                if header & 0x20 != 0 {
                    guard pos < end else { return }
                    let devCount = Int(b[pos])
                    pos += 1
                    guard pos + devCount * 3 <= end else { return }
                    for i in 0..<devCount { devBytes += Int(b[pos + i * 3 + 1]) }
                    pos += devCount * 3
                }
                defs[local] = MessageDef(globalNumber: global, bigEndian: big, fields: fields, developerBytes: devBytes)
                continue
            }

            // Data message (normal or compressed-timestamp header)
            let compressed = header & 0x80 != 0
            let local = compressed ? Int((header >> 5) & 0x03) : Int(header & 0x0F)
            guard let def = defs[local], pos + def.dataSize <= end else { return }

            var message = FitMessage(globalNumber: def.globalNumber, fields: [:])
            message.fields.reserveCapacity(def.fields.count)
            var offset = pos
            for field in def.fields {
                if let value = readValue(b, at: offset, field: field, bigEndian: def.bigEndian) {
                    message.fields[field.number] = value
                }
                offset += field.size
            }
            pos += def.dataSize

            if compressed {
                let timeOffset = Int64(header & 0x1F)
                var ts = (lastTimestamp & ~0x1F) + timeOffset
                if timeOffset < (lastTimestamp & 0x1F) { ts += 0x20 }
                lastTimestamp = ts
                message.fields[253] = .int(ts)
            } else if case .int(let ts)? = message.fields[253] {
                lastTimestamp = ts
            }
            messages.append(message)
        }
    }

    /// Reads the first element of a field. Returns nil for the FIT "invalid" sentinel.
    private static func readValue(_ b: [UInt8], at off: Int, field: FieldDef, bigEndian: Bool) -> FitValue? {
        func uint(_ n: Int) -> UInt64? {
            guard field.size >= n else { return nil }
            var v: UInt64 = 0
            for i in 0..<n {
                v = v << 8 | UInt64(b[off + (bigEndian ? i : n - 1 - i)])
            }
            return v
        }

        switch field.baseType & 0x1F {
        case 0, 2, 13: // enum, uint8, byte
            guard let v = uint(1), v != 0xFF else { return nil }
            return .int(Int64(v))
        case 10: // uint8z
            guard let v = uint(1), v != 0 else { return nil }
            return .int(Int64(v))
        case 1: // sint8
            guard let v = uint(1), v != 0x7F else { return nil }
            return .int(Int64(Int8(truncatingIfNeeded: v)))
        case 3: // sint16
            guard let v = uint(2), v != 0x7FFF else { return nil }
            return .int(Int64(Int16(truncatingIfNeeded: v)))
        case 4: // uint16
            guard let v = uint(2), v != 0xFFFF else { return nil }
            return .int(Int64(v))
        case 11: // uint16z
            guard let v = uint(2), v != 0 else { return nil }
            return .int(Int64(v))
        case 5: // sint32
            guard let v = uint(4), v != 0x7FFF_FFFF else { return nil }
            return .int(Int64(Int32(truncatingIfNeeded: v)))
        case 6: // uint32
            guard let v = uint(4), v != 0xFFFF_FFFF else { return nil }
            return .int(Int64(v))
        case 12: // uint32z
            guard let v = uint(4), v != 0 else { return nil }
            return .int(Int64(v))
        case 7: // string
            let raw = b[off..<off + field.size].prefix { $0 != 0 }
            guard !raw.isEmpty, let s = String(bytes: raw, encoding: .utf8) else { return nil }
            return .string(s)
        case 8: // float32
            guard let v = uint(4) else { return nil }
            let f = Float(bitPattern: UInt32(v))
            return f.isNaN ? nil : .double(Double(f))
        case 9: // float64
            guard let v = uint(8) else { return nil }
            let d = Double(bitPattern: v)
            return d.isNaN ? nil : .double(d)
        case 14: // sint64
            guard let v = uint(8), v != 0x7FFF_FFFF_FFFF_FFFF else { return nil }
            return .int(Int64(bitPattern: v))
        case 15: // uint64
            guard let v = uint(8), v != UInt64.max else { return nil }
            return .int(Int64(truncatingIfNeeded: v))
        case 16: // uint64z
            guard let v = uint(8), v != 0 else { return nil }
            return .int(Int64(truncatingIfNeeded: v))
        default:
            return nil
        }
    }
}
