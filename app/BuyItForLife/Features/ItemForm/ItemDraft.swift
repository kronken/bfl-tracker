import Foundation
import UIKit

/// The photo being edited in the item form.
struct DraftPhoto: Equatable {
    var original: Data
    var cutout: Data?
    var usesCutout: Bool
    // Filled in when the photo is processed in this form; nil for a version
    // that was never made into a thumbnail (only the chosen one is stored).
    var originalThumbnail: Data?
    var cutoutThumbnail: Data?
    var originalTint: String?
    var cutoutTint: String?

    init(_ processed: ProcessedPhoto) {
        original = processed.original
        cutout = processed.cutout
        usesCutout = processed.cutout != nil
        originalThumbnail = processed.originalThumbnail
        cutoutThumbnail = processed.cutoutThumbnail
        originalTint = processed.originalTint
        cutoutTint = processed.cutoutTint
    }

    init?(item: Item) {
        guard let original = item.photoOriginal else { return nil }
        self.original = original
        cutout = item.photoCutout
        usesCutout = item.usesCutout && item.photoCutout != nil
        if usesCutout {
            cutoutThumbnail = item.thumbnail
            cutoutTint = item.tintHex
        } else {
            originalThumbnail = item.thumbnail
            originalTint = item.tintHex
        }
    }

    /// Full-size data of the chosen version.
    var chosen: Data { usesCutout ? (cutout ?? original) : original }
    var chosenThumbnail: Data? { usesCutout ? cutoutThumbnail : originalThumbnail }
    var chosenTint: String? { usesCutout ? cutoutTint : originalTint }
}

/// Everything the New item / Edit item form edits, kept apart from the
/// `Item` until the user taps Add or Save.
struct ItemDraft: Equatable {
    var name = ""
    var priceText = ""
    var purchaseDate = Date.now
    var priorWearCount = 0
    var category: ItemCategory?
    var minTempC = -30
    var maxTempC = 35
    var conditions: WeatherConditions = .all
    var notes = ""
    var photo: DraftPhoto?

    var isSold = false
    var soldPriceText = ""
    var soldDate = Date.now

    static let tempLowest = -30
    static let tempHighest = 35
    static let tempStep = 5

    init() {}

    init(item: Item) {
        name = item.name
        priceText = Money.inputText(cents: item.purchasePriceCents)
        purchaseDate = item.purchaseDate
        priorWearCount = item.priorWearCount
        category = item.category
        minTempC = item.minTempC
        maxTempC = item.maxTempC
        conditions = item.conditions
        notes = item.notes
        photo = DraftPhoto(item: item)
        if let soldDate = item.soldDate {
            isSold = true
            self.soldDate = soldDate
            soldPriceText = Money.inputText(cents: item.soldPriceCents ?? 0)
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var priceCents: Int? { Money.parseCents(priceText) }
    var soldPriceCents: Int? { Money.parseCents(soldPriceText) }

    var isValid: Bool {
        !trimmedName.isEmpty && category != nil && priceCents != nil && (!isSold || soldPriceCents != nil)
    }

    // MARK: Temperature range, in 5° steps, at least 5° wide

    var canLowerMin: Bool { minTempC > Self.tempLowest }
    var canRaiseMin: Bool { minTempC + Self.tempStep <= maxTempC - Self.tempStep }
    var canLowerMax: Bool { maxTempC - Self.tempStep >= minTempC + Self.tempStep }
    var canRaiseMax: Bool { maxTempC < Self.tempHighest }

    mutating func lowerMin() { minTempC = max(Self.tempLowest, minTempC - Self.tempStep) }
    mutating func raiseMin() { if canRaiseMin { minTempC += Self.tempStep } }
    mutating func lowerMax() { if canLowerMax { maxTempC -= Self.tempStep } }
    mutating func raiseMax() { maxTempC = min(Self.tempHighest, maxTempC + Self.tempStep) }

    // MARK: Saving

    /// Writes the draft to `item`. Async because switching between original
    /// and cutout on an existing photo may need a new thumbnail.
    func apply(to item: Item) async {
        item.name = trimmedName
        item.purchasePriceCents = priceCents ?? 0
        item.purchaseDate = purchaseDate
        item.priorWearCount = max(0, priorWearCount)
        item.category = category ?? .other
        item.minTempC = minTempC
        item.maxTempC = maxTempC
        item.conditions = conditions
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if isSold {
            item.soldDate = soldDate
            item.soldPriceCents = soldPriceCents ?? 0
        } else {
            item.soldDate = nil
            item.soldPriceCents = nil
        }

        guard let photo else {
            item.photoOriginal = nil
            item.photoCutout = nil
            item.thumbnail = nil
            item.usesCutout = false
            item.tintHex = nil
            return
        }

        var thumbnail = photo.chosenThumbnail
        if thumbnail == nil {
            thumbnail = await PhotoProcessor.thumbnail(from: photo.chosen, hasAlpha: photo.usesCutout)
        }
        var tint = photo.chosenTint
        if tint == nil {
            tint = await PhotoProcessor.tintHex(from: photo.chosen)
        }

        if item.photoOriginal != photo.original { item.photoOriginal = photo.original }
        if item.photoCutout != photo.cutout { item.photoCutout = photo.cutout }
        item.usesCutout = photo.usesCutout
        item.thumbnail = thumbnail
        item.tintHex = tint
    }
}
