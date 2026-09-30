import CryptoKit
import Foundation
import Security

/// A one-time value that ties Apple's ID token to this sign-in attempt, so a
/// stolen token can't be replayed. Apple receives the SHA-256 hash; Supabase
/// receives the raw value and checks that the two match.
nonisolated enum Nonce {
    /// 64 URL-safe characters. 256 is a multiple of 64, so every character is
    /// equally likely when picked from a random byte.
    static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")

    static func random(length: Int = 32) -> String {
        precondition(length > 0, "A nonce needs at least one character")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Unable to generate a secure random nonce")
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    /// Lowercase hex SHA-256, the format Apple expects in `request.nonce`.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
