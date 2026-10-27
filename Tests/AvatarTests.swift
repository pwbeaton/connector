import Testing
@testable import App

struct InitialsTests {
    @Test func usesUpToTwoWords() {
        #expect(Initials.from("Maya") == "M")
        #expect(Initials.from("maya lee") == "ML")
        #expect(Initials.from("Maya Anne Lee") == "MA")
    }

    @Test func fallsBackToAQuestionMark() {
        #expect(Initials.from("") == "?")
        #expect(Initials.from("   ") == "?")
    }
}
