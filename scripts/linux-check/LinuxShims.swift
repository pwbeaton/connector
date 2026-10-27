import Crypto
import Foundation

// Stand-ins for Apple-only pieces (Keychain, SecRandom), used only by the Linux check.
nonisolated struct KeychainTokenStore: TokenStoring {
    func load() -> GoogleTokens? { nil }
    func save(_ tokens: GoogleTokens) throws {}
    func delete() {}
}

nonisolated enum Nonce {
    static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")
    static func random(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int(UInt8.random(in: 0...255, using: &generator)) % 64] })
    }
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated extension FileManager {
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? { nil }
}

nonisolated extension URL {
    static var applicationSupportDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("AppSupport") }
}
