import Foundation

enum LoginStep: Equatable {
    case username
    case existingPassword
    case confirmNewCharacter
    case surname
    case characterName
    case fullCharacterName
    case administratorPassword
    case confirmAdministratorPassword
    case ordinaryPassword
    case confirmOrdinaryPassword

    var title: String {
        switch self {
        case .username: "Character name"
        case .existingPassword: "Password"
        case .confirmNewCharacter: "Create this character?"
        case .surname: "Choose a Chinese surname"
        case .characterName: "Choose a Chinese given name"
        case .fullCharacterName: "Confirm the full character name"
        case .administratorPassword: "Set an administrator password"
        case .confirmAdministratorPassword: "Confirm the administrator password"
        case .ordinaryPassword: "Set your regular password"
        case .confirmOrdinaryPassword: "Confirm your regular password"
        }
    }

    var guidance: String {
        switch self {
        case .username: "Enter your existing English character name. A new name starts character creation."
        case .existingPassword: "Enter your password. It stays out of terminal output and command history."
        case .confirmNewCharacter: "The game is asking whether to create a new character. Read its prompt, then enter y or n."
        case .surname: "Enter up to two Chinese characters, or press Return to skip the surname."
        case .characterName: "Enter up to two Chinese characters for the given name."
        case .fullCharacterName: "The game needs you to type the complete Chinese name to confirm it."
        case .administratorPassword: "Choose a recovery password. NewZMud does not save it."
        case .confirmAdministratorPassword: "Re-enter the administrator password in the secure field."
        case .ordinaryPassword: "Choose the password you will use for regular logins. NewZMud does not save it."
        case .confirmOrdinaryPassword: "Re-enter the regular password in the secure field."
        }
    }

    static func detect(in text: String, passwordInput: Bool) -> LoginStep? {
        let value = text.lowercased()
        if value.contains("请再输入一次您的") && value.contains("管理密码") { return .confirmAdministratorPassword }
        if value.contains("请再输入一次您的") && value.contains("普通密码") { return .confirmOrdinaryPassword }
        if value.contains("请设定您的") && value.contains("管理密码") { return .administratorPassword }
        if value.contains("请输入你的") && value.contains("普通密码") { return .ordinaryPassword }
        if value.contains("请输入密码") || value.contains("请输入你的密码") { return .existingPassword }
        if passwordInput { return .existingPassword }
        if value.contains("请输入您的全名") || value.contains("请输入你的全名") { return .fullCharacterName }
        if value.contains("将会创造一个新的人物") || value.contains("确定吗") { return .confirmNewCharacter }
        if value.contains("中文") && value.contains("姓氏") { return .surname }
        if value.contains("中文") && value.contains("名字") { return .characterName }
        if value.contains("英文名字") || value.contains("character name") || value.contains("enter name") { return .username }
        return nil
    }
}

