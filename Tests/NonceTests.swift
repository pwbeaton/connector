import Testing
@testable import App

struct NonceTests {
    @Test func randomNonceHasRequestedLength() {
        #expect(Nonce.random().count == 32)
        #expect(Nonce.random(length: 8).count == 8)
    }

    @Test func randomNonceUsesOnlyAllowedCharacters() {
        let allowed = Set(Nonce.characters)
        #expect(Nonce.random(length: 256).allSatisfy { allowed.contains($0) })
    }

    @Test func alphabetHas64Characters() {
        // 64 divides 256, so random bytes map evenly onto characters.
        #expect(Nonce.characters.count == 64)
        #expect(Set(Nonce.characters).count == 64)
    }

    @Test func randomNoncesDiffer() {
        #expect(Nonce.random() != Nonce.random())
    }

    @Test func sha256MatchesKnownVector() {
        // FIPS 180-2 test vector for "abc".
        #expect(Nonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
