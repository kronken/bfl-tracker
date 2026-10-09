import Foundation
import UIKit
import Testing
@testable import BuyItForLife

struct MoneyTests {
    @Test(arguments: [
        ("349", 34_900),
        ("349.90", 34_990),
        ("349,90", 34_990),
        ("349,9", 34_990),
        ("1 299", 129_900),
        ("1,299", 129_900),       // three digits after the separator: grouping
        ("1.299,50", 129_950),
        ("1,299.50", 129_950),
        ("€ 120", 12_000),
        ("0", 0),
        (",5", 50),
    ])
    func parsesTypedPrices(input: String, cents: Int) {
        #expect(Money.parseCents(input) == cents)
    }

    @Test func rejectsInputWithoutDigits() {
        #expect(Money.parseCents("") == nil)
        #expect(Money.parseCents("€") == nil)
        #expect(Money.parseCents(",") == nil)
    }

    @Test func formatsWholeAmountsWithoutDecimals() {
        let finland = Locale(identifier: "fi_FI")
        #expect(Money.format(cents: 34_900, locale: finland) == "349\u{A0}€")
        #expect(Money.format(cents: 34_990, locale: finland) == "349,90\u{A0}€")
        let us = Locale(identifier: "en_US")
        #expect(Money.format(cents: 34_900, locale: us) == "$349")
    }

    @Test func formatsCostPerWearWithTwoDecimals() {
        let us = Locale(identifier: "en_US")
        #expect(Money.format(fractionalCents: 84.7, locale: us) == "$0.85")
    }

    @Test func inputTextRoundTrips() {
        let finland = Locale(identifier: "fi_FI")
        #expect(Money.inputText(cents: 34_900, locale: finland) == "349")
        #expect(Money.parseCents(Money.inputText(cents: 129_950, locale: finland)) == 129_950)
    }
}

struct TemperatureTests {
    @Test func celsiusUsesRealMinusSign() {
        let finland = Locale(identifier: "fi_FI")
        #expect(Temperature.format(celsius: -20, locale: finland) == "\u{2212}20°C")
        #expect(Temperature.format(celsius: 15, locale: finland) == "15°C")
    }

    @Test func fahrenheitInTheUS() {
        let us = Locale(identifier: "en_US")
        #expect(Temperature.format(celsius: -20, locale: us) == "\u{2212}4°F")
        #expect(Temperature.format(celsius: 35, locale: us) == "95°F")
    }
}

struct PhotoTintTests {
    @Test func fallbackTintIsStable() {
        // FNV-1a must give the same value on every launch.
        #expect(ItemImageView.stableHash("") == 0xCBF2_9CE4_8422_2325)
        #expect(ItemImageView.stableHash("a") == 0xAF63_DC4C_8601_EC8C)
    }

    @Test func darkTintIsDarkAndKeepsHue() {
        let hex = PhotoProcessor.darkTint(red: 0.6, green: 0.4, blue: 0.2) // leather brown
        let value = UInt32(hex.dropFirst(), radix: 16)!
        let r = (value >> 16) & 0xFF, g = (value >> 8) & 0xFF, b = value & 0xFF
        #expect(max(r, g, b) <= 0x2C)
        #expect(r > g && g > b)
    }
}

struct ItemDraftTests {
    @Test func temperatureRangeStaysAtLeastFiveDegreesWide() {
        var draft = ItemDraft()
        draft.minTempC = 10
        draft.maxTempC = 15
        #expect(!draft.canRaiseMin)
        #expect(!draft.canLowerMax)
        draft.raiseMin()
        draft.lowerMax()
        #expect(draft.minTempC == 10)
        #expect(draft.maxTempC == 15)
    }

    @Test func temperatureRangeStopsAtScaleEnds() {
        var draft = ItemDraft()
        #expect(!draft.canLowerMin)
        #expect(!draft.canRaiseMax)
        draft.lowerMin()
        draft.raiseMax()
        #expect(draft.minTempC == -30)
        #expect(draft.maxTempC == 35)
    }

    @Test func validityNeedsNameCategoryAndPrice() {
        var draft = ItemDraft()
        #expect(!draft.isValid)
        draft.name = "  Red Wing Iron Ranger  "
        draft.priceText = "349"
        #expect(!draft.isValid)
        draft.category = .footwear
        #expect(draft.isValid)
        #expect(draft.trimmedName == "Red Wing Iron Ranger")
        draft.isSold = true
        #expect(!draft.isValid)
        draft.soldPriceText = "180"
        #expect(draft.isValid)
    }
}

struct PhotoProcessorTests {
    /// A 3000×2000 brown rectangle on white, like a boot on a floor.
    private func sampleImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
            UIColor(red: 0.45, green: 0.28, blue: 0.15, alpha: 1).setFill()
            context.fill(CGRect(x: 900, y: 600, width: 1200, height: 800))
        }
    }

    @Test func resizesToStoredSizes() async throws {
        let processed = try #require(await PhotoProcessor.process(sampleImage()))
        let original = try #require(UIImage(data: processed.original))
        let thumbnail = try #require(UIImage(data: processed.originalThumbnail))
        #expect(original.size.width * original.scale == 1200)
        #expect(original.size.height * original.scale == 800)
        #expect(thumbnail.size.width * thumbnail.scale == 600)
        #expect(processed.originalTint.hasPrefix("#") && processed.originalTint.count == 7)
        // Well under the ~250 KB budget for a 1200 px image.
        #expect(processed.original.count < 250_000)
    }
}

struct CompactMoneyTests {
    @Test func compactsThousands() {
        let us = Locale(identifier: "en_US")
        #expect(SpendPerYearCard.compact(62_900, locale: us) == "$629")
        #expect(SpendPerYearCard.compact(130_400, locale: us) == "$1.3K")
        // Never "€k" glued after the symbol.
        #expect(!SpendPerYearCard.compact(130_400, locale: Locale(identifier: "fi_FI")).contains("€k"))
    }
}

struct TemperatureBandTests {
    @Test func bandsSpanFromColdestToWarmest() {
        #expect(TemperatureBand.range(of: []) == nil)
        #expect(TemperatureBand.range(of: [.cold]) == 0...10)
        #expect(TemperatureBand.range(of: [.freezing, .cold, .mild]) == -30...18)
        // A gap still gives one continuous range.
        #expect(TemperatureBand.range(of: [.freezing, .warm]) == -30...35)
    }
}
