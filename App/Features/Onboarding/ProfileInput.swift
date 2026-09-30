import UIKit

/// Rules for the name friends see. Matches the database limit of 40 characters.
nonisolated enum DisplayName {
    static let maxLength = 40

    /// The trimmed name, or nil if it's empty or too long.
    static func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}

/// Turns a picked photo into a small square JPEG for upload.
enum AvatarImage {
    /// Center-crops to a square and scales down to at most `maxPixels` wide.
    /// Small photos are never scaled up.
    static func jpegData(from image: UIImage, maxPixels: CGFloat = 512, quality: CGFloat = 0.8) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let side = min(pixelWidth, pixelHeight)
        guard side > 0 else { return nil }
        let outputSide = min(side, maxPixels).rounded(.down)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
        let scale = outputSide / side
        let drawSize = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
        let origin = CGPoint(x: (outputSide - drawSize.width) / 2, y: (outputSide - drawSize.height) / 2)
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
