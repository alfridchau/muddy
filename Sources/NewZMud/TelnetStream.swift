import Foundation

/// Stateful Telnet framing, text decoding, and removal of terminal controls.
/// Every state survives TCP reads, including partial IAC, ANSI, and multibyte text sequences.
struct TelnetStream {
    struct Output {
        var text = ""
        var terminalText = ""
        var reply = Data()
        var passwordInput: Bool?
        var gmcpEnabled: Bool?
        var messages: [GMCPMessage] = []
    }

    private enum State {
        case text, command, option(UInt8), subnegotiation, subcommand
    }
    private enum Escape {
        case text, start, intermediate, csi, osc, oscEnd
    }

    private var state = State.text
    private var escape = Escape.text
    private var subnegotiation: [UInt8] = []
    private var displayBytes: [UInt8] = []
    private var terminalBytes: [UInt8] = []
    private var textEncoding: String.Encoding
    private var subnegotiationOverflow = false
    private var columns = 80
    private var rows = 30
    private var remoteOptions: Set<UInt8> = []
    private var localOptions: Set<UInt8> = []

    init(encoding: String.Encoding = .utf8) {
        textEncoding = encoding
    }

    mutating func setTextEncoding(_ encoding: String.Encoding) {
        guard textEncoding != encoding else { return }
        textEncoding = encoding
        displayBytes.removeAll(keepingCapacity: true)
        terminalBytes.removeAll(keepingCapacity: true)
    }

    mutating func receive(_ data: Data) -> Output {
        var output = Output()
        for byte in data {
            switch state {
            case .text:
                if byte == 255 { state = .command }
                else { consumeText(byte) }
            case .command:
                switch byte {
                case 255: consumeText(255); state = .text
                case 251...254: state = .option(byte)
                case 250:
                    subnegotiation.removeAll(keepingCapacity: true)
                    subnegotiationOverflow = false
                    state = .subnegotiation
                default: state = .text // GA, EOR, NOP, and other standalone commands
                }
            case .option(let command):
                negotiate(command, option: byte, output: &output)
                state = .text
            case .subnegotiation:
                if byte == 255 { state = .subcommand }
                else if subnegotiation.count < 65_536 { subnegotiation.append(byte) }
                else { subnegotiationOverflow = true }
            case .subcommand:
                if byte == 240 {
                    finishSubnegotiation(output: &output)
                    state = .text
                } else {
                    if byte == 255 {
                        if subnegotiation.count < 65_536 { subnegotiation.append(byte) }
                        else { subnegotiationOverflow = true }
                    }
                    state = .subnegotiation
                }
            }
        }
        output.text = Self.decodeAvailableText(&displayBytes, encoding: textEncoding)
        output.terminalText = Self.decodeAvailableText(&terminalBytes, encoding: textEncoding)
        return output
    }

    private mutating func negotiate(_ command: UInt8, option: UInt8, output: inout Output) {
        switch command {
        case 251: // WILL: the server offers to perform an option.
            if option == 1 || option == 3 || option == 201 { // ECHO, SGA, GMCP
                let hadGMCP = remoteOptions.contains(201) || localOptions.contains(201)
                if remoteOptions.insert(option).inserted { output.reply.append(contentsOf: [255, 253, option]) }
                if option == 1 { output.passwordInput = true }
                if option == 201 && !hadGMCP { output.gmcpEnabled = true }
            } else {
                // Compression stays disabled until a streaming decompressor is present.
                output.reply.append(contentsOf: [255, 254, option])
            }
        case 252: // WONT
            if remoteOptions.remove(option) != nil { output.reply.append(contentsOf: [255, 254, option]) }
            if option == 1 { output.passwordInput = false }
            if option == 201 { output.gmcpEnabled = localOptions.contains(201) }
        case 253: // DO: the server asks us to perform an option.
            if option == 3 || option == 24 || option == 31 || option == 201 {
                let hadGMCP = remoteOptions.contains(201) || localOptions.contains(201)
                if localOptions.insert(option).inserted {
                    output.reply.append(contentsOf: [255, 251, option])
                    if option == 31 { // NAWS: conservative initial terminal dimensions.
                        output.reply.append(windowSize())
                    }
                    if option == 201 && !hadGMCP { output.gmcpEnabled = true }
                }
            } else {
                output.reply.append(contentsOf: [255, 252, option])
            }
        case 254: // DONT
            if localOptions.remove(option) != nil { output.reply.append(contentsOf: [255, 252, option]) }
            if option == 201 { output.gmcpEnabled = remoteOptions.contains(201) }
        default: break
        }
    }

    private mutating func finishSubnegotiation(output: inout Output) {
        guard !subnegotiationOverflow else { return }
        if subnegotiation.first == 24, localOptions.contains(24), subnegotiation.dropFirst().first == 1 {
            output.reply.append(contentsOf: [255, 250, 24, 0]) // TTYPE IS
            output.reply.append(contentsOf: "NEWZMUD".utf8)
            output.reply.append(contentsOf: [255, 240])
        }
        if subnegotiation.first == 201, remoteOptions.contains(201) || localOptions.contains(201),
           let message = GMCPMessage(String(decoding: subnegotiation.dropFirst(), as: UTF8.self)) {
            output.messages.append(message)
        }
    }

    static func subnegotiation(option: UInt8, bytes: [UInt8]) -> Data {
        var result = Data([255, 250, option])
        for byte in bytes {
            result.append(byte)
            if byte == 255 { result.append(255) }
        }
        result.append(contentsOf: [255, 240])
        return result
    }

    static func gmcp(_ message: String) -> Data {
        subnegotiation(option: 201, bytes: Array(message.utf8))
    }

    mutating func resize(columns: Int, rows: Int) -> Data {
        self.columns = max(20, min(500, columns)); self.rows = max(5, min(200, rows))
        return localOptions.contains(31) ? windowSize() : Data()
    }

    private func windowSize() -> Data {
        Self.subnegotiation(option: 31, bytes: [UInt8(columns >> 8), UInt8(columns & 255), UInt8(rows >> 8), UInt8(rows & 255)])
    }

    private mutating func consumeText(_ byte: UInt8) {
        terminalBytes.append(byte)
        switch escape {
        case .text:
            if byte == 27 { escape = .start }
            else if byte >= 32 || byte == 9 || byte == 10 || byte == 13 || byte == 8 { displayBytes.append(byte) }
        case .start:
            if byte == 91 { escape = .csi }
            else if byte == 93 { escape = .osc }
            else if (32...47).contains(byte) { escape = .intermediate }
            else { escape = .text }
        case .intermediate:
            if !(32...47).contains(byte) { escape = .text }
        case .csi:
            if (64...126).contains(byte) { escape = .text }
        case .osc:
            if byte == 7 { escape = .text }
            else if byte == 27 { escape = .oscEnd }
        case .oscEnd:
            if byte == 92 || byte == 7 { escape = .text }
            else if byte != 27 { escape = .osc }
        }
    }

    private static func decodeAvailableText(_ bytes: inout [UInt8], encoding: String.Encoding) -> String {
        guard !bytes.isEmpty else { return "" }
        if encoding == .utf8 {
            var end = bytes.count
            var lead = bytes.count - 1
            while lead > 0 && bytes[lead] & 0xC0 == 0x80 { lead -= 1 }
            let byte = bytes[lead]
            let length: Int
            switch byte {
            case 0xC2...0xDF: length = 2
            case 0xE0...0xEF: length = 3
            case 0xF0...0xF4: length = 4
            default: length = 1
            }
            if length > bytes.count - lead { end = lead }
            let text = String(decoding: bytes[..<end], as: UTF8.self)
            bytes.removeFirst(end)
            return text
        }

        if let text = String(data: Data(bytes), encoding: encoding) {
            bytes.removeAll(keepingCapacity: true)
            return text
        }
        // Keep a short suffix so a split GBK/Shift-JIS/GB18030 character can finish on the next read.
        if bytes.count > 4 {
            for end in stride(from: bytes.count - 1, through: bytes.count - 4, by: -1) {
                if let text = String(data: Data(bytes[..<end]), encoding: encoding) {
                    bytes.removeFirst(end)
                    return text
                }
            }
        }
        return ""
    }
}
