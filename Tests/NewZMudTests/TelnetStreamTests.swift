import XCTest
@testable import NewZMud

final class TelnetStreamTests: XCTestCase {
    func testChineseAndEmojiSurviveEveryPacketBoundary() {
        let message = "欢迎来到炎黄群侠传 👋\r\n您的英文名字："
        let bytes = Array(message.utf8)
        for split in 0...bytes.count {
            var stream = TelnetStream()
            let first = stream.receive(Data(bytes[..<split]))
            let second = stream.receive(Data(bytes[split...]))
            XCTAssertEqual(first.text + second.text, message, "Split at byte \(split)")
        }
    }

    func testTelnetAndANSISurviveSingleBytePackets() {
        var stream = TelnetStream()
        let bytes = [UInt8]("\u{1B}[31m炎黄\u{1B}[0m\r\n".utf8) + [255, 253, 24]
            + [UInt8]("江湖".utf8)
        var text = ""
        var reply = Data()
        for byte in bytes {
            let output = stream.receive(Data([byte]))
            text += output.text
            reply.append(output.reply)
        }
        XCTAssertEqual(text, "炎黄\r\n江湖")
        XCTAssertEqual(reply, Data([255, 251, 24]))
    }

    func testPasswordEchoNegotiation() {
        var stream = TelnetStream()
        let secret = stream.receive(Data([255, 251, 1]))
        XCTAssertEqual(secret.passwordInput, true)
        XCTAssertEqual(secret.reply, Data([255, 253, 1]))
        XCTAssertTrue(stream.receive(Data([255, 251, 1])).reply.isEmpty)
        let normal = stream.receive(Data([255, 252, 1]))
        XCTAssertEqual(normal.passwordInput, false)
        XCTAssertEqual(normal.reply, Data([255, 254, 1]))
    }

    func testTerminalTypeAndWindowSize() {
        var stream = TelnetStream()
        _ = stream.receive(Data([255, 253, 24]))
        _ = stream.receive(Data([255, 250, 24]))
        let reply = stream.receive(Data([1, 255, 240])).reply
        XCTAssertEqual(reply, Data([255, 250, 24, 0] + Array("NEWZMUD".utf8) + [255, 240]))
        XCTAssertEqual(stream.receive(Data([255, 253, 31])).reply,
                       Data([255, 251, 31, 255, 250, 31, 0, 80, 0, 30, 255, 240]))
    }

    func testCompressionIsRefusedAndGMCPIsAccepted() {
        var stream = TelnetStream()
        let output = stream.receive(Data([255, 251, 86, 255, 251, 201, 255, 253, 99]))
        XCTAssertEqual(output.reply, Data([255, 254, 86, 255, 253, 201, 255, 252, 99]))
        XCTAssertEqual(output.gmcpEnabled, true)
        XCTAssertEqual(output.text, "")
    }

    func testFragmentedGMCPAndANSIAreDeliveredSeparately() {
        var stream = TelnetStream()
        _ = stream.receive(Data([255, 251, 201]))
        let message = #"Char.Vitals {"hp":820,"neili":360}"#
        let raw = Array(TelnetStream.gmcp(message)) + Array("\u{1B}[32m江湖\u{1B}[0m".utf8)
        var messages: [GMCPMessage] = []
        var text = ""
        for byte in raw {
            let output = stream.receive(Data([byte]))
            messages += output.messages
            text += output.terminalText
        }
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.module, "Char.Vitals")
        XCTAssertEqual(messages.first?.object?["hp"] as? Int, 820)
        XCTAssertEqual(text, "\u{1B}[32m江湖\u{1B}[0m")
    }

    func testNAWSEscapes255AndUsesLatestDimensions() {
        var stream = TelnetStream()
        _ = stream.resize(columns: 255, rows: 40)
        let reply = stream.receive(Data([255, 253, 31])).reply
        XCTAssertEqual(reply, Data([255, 251, 31, 255, 250, 31, 0, 255, 255, 0, 40, 255, 240]))
    }

    func testOSCMetadataIsNotShownAsGameText() {
        var stream = TelnetStream()
        XCTAssertEqual(stream.receive(Data("\u{1B}]0;window title".utf8)).text, "")
        XCTAssertEqual(stream.receive(Data("\u{7}扬州\u{1B}]8;;https://example.com\u{1B}".utf8)).text, "扬州")
        XCTAssertEqual(stream.receive(Data("\\客店\u{1B}]8;;\u{1B}\\".utf8)).text, "客店")
    }
}
