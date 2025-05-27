//
// MarketCoin.swift
// CryptoSage
//

import Foundation

// MARK: - Sparkline helper
struct SparklineIn7D: Codable {
    let price: [Double]
}

/// Represents a single coin returned by the CoinGecko `/coins/markets` endpoint.
struct MarketCoin: Identifiable, Codable {
    let id: String
    let symbol: String
    let name: String
    let image: String
    var currentPrice: Double
    /// 24-hour price change percentage from API (in currency)
    let priceChangePercentage24hInCurrency: Double?
    var totalVolume: Double
    var marketCap: Double
    let marketCapRank: Int?
    var sparkline7d: SparklineIn7D?

    /// 1-hour price change percentage from API (in currency)
    let priceChangePercentage1hInCurrency: Double?

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, image
        // 24-hour price change percentage from API
        case priceChangePercentage24hInCurrency = "price_change_percentage_24h_in_currency"
        /// 1-hour price change percentage from API (in currency)
        case priceChangePercentage1hInCurrency = "price_change_percentage_1h_in_currency"
        case currentPrice             = "current_price"
        case totalVolume              = "total_volume"
        case marketCap                = "market_cap"
        case marketCapRank            = "market_cap_rank"
        case sparkline7d              = "sparkline_in_7d"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decode(String.self, forKey: .name)
        image = try container.decode(String.self, forKey: .image)
        currentPrice = try container.decode(Double.self, forKey: .currentPrice)
        totalVolume = try container.decode(Double.self, forKey: .totalVolume)
        marketCap = try container.decode(Double.self, forKey: .marketCap)
        marketCapRank = try container.decodeIfPresent(Int.self, forKey: .marketCapRank)
        sparkline7d = try? container.decode(SparklineIn7D.self, forKey: .sparkline7d)
        priceChangePercentage24hInCurrency = try container.decodeIfPresent(Double.self, forKey: .priceChangePercentage24hInCurrency)
        priceChangePercentage1hInCurrency = try container.decodeIfPresent(Double.self, forKey: .priceChangePercentage1hInCurrency)
    }

    /// Convenience alias for sparkline price array
    var sparklineData: [Double] {
        sparkline7d?.price ?? []
    }

    // MARK: - UI Compatibility Additions

    /// Fallback (0) if API field is nil
    var priceChangePercentage24h: Double { priceChangePercentage24hInCurrency ?? 0 }
    /// Percentage change over the last hour, computed from sparkline first, then API
    var priceChangePercentage1h: Double {
        // 1) Compute from sparkline if available
        if let prices = sparkline7d?.price, prices.count >= 2 {
            let last = prices.last!
            let prev = prices[prices.count - 2]
            let pct = (last - prev) / prev * 100
            print("↪️ [MarketCoin] Sparkline comp 1h for \(symbol): \(pct)%")
            return pct
        }
        // 2) Fallback to API value if present
        if let change = priceChangePercentage1hInCurrency {
            print("↪️ [MarketCoin] API fallback 1h for \(symbol): \(change)%")
            return change
        }
        // 3) No data available
        print("↪️ [MarketCoin] No data for 1h for \(symbol)")
        return 0
    }

    /// Local favorite flag for UI toggling
    var isFavorite: Bool = false

    /// Backward‐compatible properties for existing code
    var price: Double {
        get { currentPrice }
        set { currentPrice = newValue }
    }
    /// Mutable alias for sparkline array
    var sparklineDataMutable: [Double] {
        get { sparklineData }
        set { sparkline7d = SparklineIn7D(price: newValue) }
    }
    var dailyChange: Double { priceChangePercentage24h }
    /// Backward-compatibility for hourly change
    var hourlyChange: Double { priceChangePercentage1h }
    /// Safely create a URL by percent-encoding the image string
    var imageUrl: URL? {
        if let encodedString = image.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: encodedString)
        }
        return URL(string: image)
    }
    var finalImageUrl: URL? { imageUrl }

    /// Backward‑compatible alias for sparkline data array
    var sparkline: [Double] {
        sparklineData
    }

    /// Backward‑compatible alias for total volume
    var volume: Double {
        totalVolume
    }

    /// Convenience initializer to support manual `MarketCoin(...)` calls
    init(
        id: String,
        symbol: String,
        name: String,
        imageUrl: URL?,
        finalImageUrl: URL?,
        price: Double,
        dailyChange: Double,
        volume: Double,
        marketCap: Double,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        // Prefer the finalImageUrl if provided
        self.image = finalImageUrl?.absoluteString ?? ""
        self.currentPrice = price
        self.priceChangePercentage24hInCurrency = dailyChange
        self.totalVolume = volume
        self.marketCap = marketCap
        self.marketCapRank = nil
        // For manual coins, no sparkline data
        self.sparkline7d = nil
        self.isFavorite = isFavorite
        self.priceChangePercentage1hInCurrency = 0
    }

    /// Convenience initializer for calls that pass image URL as String
    init(
        id: String,
        symbol: String,
        name: String,
        image: String,
        price: Double,
        dailyChange: Double,
        volume: Double,
        marketCap: Double,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.image = image
        self.currentPrice = price
        self.priceChangePercentage24hInCurrency = dailyChange
        self.totalVolume = volume
        self.marketCap = marketCap
        self.marketCapRank = nil
        self.sparkline7d = nil
        self.priceChangePercentage1hInCurrency = 0
        self.isFavorite = isFavorite
    }
}
