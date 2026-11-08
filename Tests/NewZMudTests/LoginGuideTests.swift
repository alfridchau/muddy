import XCTest
@testable import NewZMud

final class LoginGuideTests: XCTestCase {
    func testRecognizesTheLocalGamesLoginAndNewCharacterPrompts() {
        XCTAssertEqual(LoginStep.detect(in: "您的英文名字(新玩家可以选择一喜欢的名字)：", passwordInput: false), .username)
        XCTAssertEqual(LoginStep.detect(in: "请输入密码：", passwordInput: false), .existingPassword)
        XCTAssertEqual(LoginStep.detect(in: "使用这个名字将会创造一个新的人物，您确定吗？", passwordInput: false), .confirmNewCharacter)
        XCTAssertEqual(LoginStep.detect(in: "请输入您的中文姓氏(不要超过两个汉字)：", passwordInput: false), .surname)
        XCTAssertEqual(LoginStep.detect(in: "请输入您的中文名字(不要超过两个汉字)：", passwordInput: false), .characterName)
        XCTAssertEqual(LoginStep.detect(in: "请输入您的全名(即姓和名字的组合)：", passwordInput: false), .fullCharacterName)
    }

    func testSecureModeDistinguishesNewAccountPasswordSteps() {
        XCTAssertEqual(LoginStep.detect(in: "请设定您的管理密码：", passwordInput: true), .administratorPassword)
        XCTAssertEqual(LoginStep.detect(in: "请再输入一次您的管理密码，以确认：", passwordInput: true), .confirmAdministratorPassword)
        XCTAssertEqual(LoginStep.detect(in: "请输入你的普通密码：", passwordInput: true), .ordinaryPassword)
        XCTAssertEqual(LoginStep.detect(in: "请再输入一次您的普通密码：", passwordInput: true), .confirmOrdinaryPassword)
        XCTAssertEqual(LoginStep.detect(in: "", passwordInput: true), .existingPassword)
    }
}
