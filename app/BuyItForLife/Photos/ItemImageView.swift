import SwiftUI
import UIKit

/// What an item's image square shows. Built from an `Item` or from a form
/// draft, so the form preview matches the rest of the app.
struct ItemImageContent: Equatable {
    var imageData: Data?
    var isCutout: Bool
    var tintHex: String?
    var name: String
    var category: ItemCategory
}

extension Item {
    var thumbnailContent: ItemImageContent {
        ItemImageContent(imageData: thumbnail, isCutout: usesCutout, tintHex: tintHex, name: name, category: category)
    }
}

/// The square that represents an item: its photo, its cutout on its tint, or
/// a colour block with the category icon when there is no photo.
struct ItemImageView: View {
    var content: ItemImageContent
    var cornerRadius: CGFloat
    /// Size of the category icon in the no-photo state.
    var iconSize: CGFloat = 24

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(tint)
            if let image {
                if content.isCutout {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(cutoutPadding)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else if content.imageData == nil {
                CategoryIcon(category: content.category, size: iconSize)
                    .foregroundStyle(.textSecondary)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: content.imageData) {
            image = await ImageCache.shared.image(for: content.imageData)
        }
        .accessibilityHidden(true)
    }

    private var tint: Color {
        content.tintHex.flatMap(Color.init(hexString:)) ?? Self.fallbackTint(for: content.name)
    }

    private var cutoutPadding: CGFloat { iconSize * 0.4 }

    /// Dark tints from the designs, picked by a stable hash of the name so an
    /// item without a photo always gets the same colour.
    static let fallbackTints: [UInt32] = [
        0x2A1F16, 0x2B1B1B, 0x151B2B, 0x1C2216, 0x25231D,
        0x2A2219, 0x22221E, 0x1F2119, 0x261C14, 0x1C1714,
    ]

    static func fallbackTint(for name: String) -> Color {
        Color(hex: fallbackTints[Int(stableHash(name) % UInt64(fallbackTints.count))])
    }

    /// FNV-1a. Swift's `hashValue` changes between launches, so it can't be used.
    nonisolated static func stableHash(_ string: String) -> UInt64 {
        string.utf8.reduce(0xCBF2_9CE4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}

/// A category's line icon, drawn in the current foreground style.
struct CategoryIcon: View {
    var category: ItemCategory
    var size: CGFloat = 24

    var body: some View {
        Image("Categories/\(category.rawValue)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Decodes stored images off the main thread and keeps recent ones in memory.
actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSData, UIImage>()

    init() {
        cache.countLimit = 200
    }

    func image(for data: Data?) async -> UIImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = await UIImage(data: data)?.byPreparingForDisplay() else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
