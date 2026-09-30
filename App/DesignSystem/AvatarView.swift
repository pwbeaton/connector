import SwiftUI
import UIKit

/// A round profile photo, falling back to initials when there's no photo.
struct AvatarView: View {
    let name: String
    var url: URL?
    /// A photo picked but not uploaded yet; shown instead of `url`.
    var localImage: UIImage?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage).resizable().scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityElement()
        .accessibilityLabel(name.isEmpty ? "Profile photo" : "\(name)'s profile photo")
    }

    private var initials: some View {
        Circle()
            .fill(.tint.opacity(0.15))
            .overlay {
                Text(Initials.from(name))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tint)
            }
    }
}

/// Up to two initials from a display name: "Maya" → "M", "Maya Lee" → "ML".
nonisolated enum Initials {
    static func from(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

#Preview {
    HStack {
        AvatarView(name: "Maya Lee", size: 64)
        AvatarView(name: "", size: 64)
    }
}
