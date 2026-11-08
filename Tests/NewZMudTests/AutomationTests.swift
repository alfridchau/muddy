import XCTest
@testable import NewZMud

final class AutomationTests: XCTestCase {
    func testAliasesExpandArgumentsAndStopCycles() throws {
        let rules = [AliasRule(name: "greet", commands: "say Hello $*;look $1"),
                     AliasRule(name: "a", commands: "b"), AliasRule(name: "b", commands: "a")]
        XCTAssertEqual(try CommandExpansion.aliases("greet old man", rules: rules), ["say Hello old man", "look old"])
        XCTAssertThrowsError(try CommandExpansion.aliases("a", rules: rules))
    }
    func testCaptureSubstitutionIsLiteralAndOptionalGroupsAreEmpty() {
        let rule = TriggerRule(pattern: #"^hello (\S+)(?: (\S+))?$"#, commands: "say $1 / $2;look $0")
        XCTAssertEqual(CommandExpansion.trigger(rule, line: "hello $2"), ["say $2 /", "look hello $2"])
        XCTAssertNil(CommandExpansion.trigger(rule, line: "not hello"))
    }
    func testSpeedwalkValidatesTheWholePathBeforeSending() throws {
        XCTAssertEqual(try CommandExpansion.walk("2n, 3e 2sw u"), ["n", "n", "e", "e", "e", "sw", "sw", "u"])
        for path in ["2nBOOM3e", "0n", "101n", "999999999999999999999n", ""] {
            XCTAssertThrowsError(try CommandExpansion.walk(path), path)
        }
    }
    func testHistoryRestoresUnsentDraftAtTheBottom() {
        var recall = CommandRecall()
        let history = ["look", "score"]
        XCTAssertEqual(recall.move(up: true, current: "say hello", history: history), "score")
        XCTAssertEqual(recall.move(up: true, current: "score", history: history), "look")
        XCTAssertEqual(recall.move(up: false, current: "look", history: history), "score")
        XCTAssertEqual(recall.move(up: false, current: "score", history: history), "say hello")
    }
    func testCompletionCyclesBothWaysWithinTheCurrentWord() {
        var completion = CommandCompletion()
        let words = ["north", "northeast", "northwest"]
        XCTAssertEqual(completion.complete("go nor", words: words), "go north")
        XCTAssertEqual(completion.complete("go north", words: words), "go northeast")
        XCTAssertEqual(completion.complete("go northeast", words: words, backwards: true), "go north")
        completion.reset()
        XCTAssertEqual(completion.complete("nor", words: words, backwards: true), "northwest")
    }
    func testWorldConfigurationRoundTripPreservesRulesAndPreferences() throws {
        var configuration = WorldConfiguration()
        configuration.autoReconnect = true
        configuration.aliases = [AliasRule(name: "home", commands: "/walk 2n3e")]
        configuration.triggers = [TriggerRule(pattern: "hungry", commands: "eat bread")]
        configuration.timers = [TimerRule(enabled: true, name: "Status", interval: 10, commands: "hp")]
        configuration.keys = [KeyRule(key: "h", command: true, commands: "home")]
        XCTAssertEqual(try JSONDecoder().decode(WorldConfiguration.self, from: JSONEncoder().encode(configuration)), configuration)
    }
    func testReconnectDelaysAreBounded() {
        XCTAssertEqual((1...5).compactMap(ReconnectPolicy.delay), [3, 6, 12, 24, 30])
        XCTAssertNil(ReconnectPolicy.delay(for: 6))
    }
    func testGenericGMCPVitalsAndRoomExits() throws {
        var character = CharacterState()
        character.receive(try XCTUnwrap(GMCPMessage(#"Char.Vitals {"hp":820,"max_hp":1000,"jing":240,"max_jing":300,"jingli":180,"max_jingli":300,"neili":360,"max_neili":500,"exp":12450}"#)))
        character.receive(try XCTUnwrap(GMCPMessage(#"Room.Info {"name":"扬州广场","area":"city","exits":["north","east"]}"#)))
        let vitals = Dictionary(uniqueKeysWithValues: character.vitals.map { ($0.id, $0) })
        XCTAssertEqual(vitals["hp"]?.fraction ?? 0, 0.82, accuracy: 0.001)
        XCTAssertEqual(vitals["neili"]?.current, 360)
        XCTAssertEqual(vitals["jing"]?.current, 240)
        XCTAssertEqual(vitals["jingli"]?.name, "Jingli")
        XCTAssertEqual(character.experience, 12450)
        XCTAssertEqual(character.room, "扬州广场")
        XCTAssertEqual(character.exits, ["north", "east"])
    }
}
