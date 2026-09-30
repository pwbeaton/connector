import Foundation
import Testing
import UIKit
@testable import App

struct DisplayNameTests {
    @Test func trimsSpacesAndNewlines() {
        #expect(DisplayName.clean("  Maya \n") == "Maya")
    }

    @Test func rejectsBlankNames() {
        #expect(DisplayName.clean("") == nil)
        #expect(DisplayName.clean("   ") == nil)
    }

    @Test func acceptsUpToTheDatabaseLimit() {
        let longest = String(repeating: "a", count: DisplayName.maxLength)
        #expect(DisplayName.clean(longest) == longest)
        #expect(DisplayName.clean(longest + "a") == nil)
    }
}

struct AvatarPathTests {
    @Test func folderIsTheLowercaseUserID() throws {
        // Storage policies compare the folder with auth.uid()::text, which is lowercase.
        let userID = try #require(UUID(uuidString: "A11CE000-0000-4000-8000-000000000001"))
        let path = AvatarPath.make(userID: userID)
        #expect(path.hasPrefix("a11ce000-0000-4000-8000-000000000001/"))
        #expect(path.hasSuffix(".jpg"))
        #expect(path == path.lowercased())
    }

    @Test func everyUploadGetsANewFileName() {
        let userID = UUID()
        #expect(AvatarPath.make(userID: userID) != AvatarPath.make(userID: userID))
    }
}

struct AvatarImageTests {
    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func largePhotosBecomeA512PixelSquare() throws {
        let data = try #require(AvatarImage.jpegData(from: makeImage(width: 2000, height: 1000)))
        let result = try #require(UIImage(data: data))
        #expect(result.size.width * result.scale == 512)
        #expect(result.size.height * result.scale == 512)
    }

    @Test func smallPhotosAreCroppedButNotEnlarged() throws {
        let data = try #require(AvatarImage.jpegData(from: makeImage(width: 100, height: 80)))
        let result = try #require(UIImage(data: data))
        #expect(result.size.width * result.scale == 80)
        #expect(result.size.height * result.scale == 80)
    }

    @Test func outputStaysWellUnderTheUploadLimit() throws {
        // The avatars bucket accepts files up to 1 MB.
        let data = try #require(AvatarImage.jpegData(from: makeImage(width: 4000, height: 3000)))
        #expect(data.count < 1_048_576)
    }
}

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
