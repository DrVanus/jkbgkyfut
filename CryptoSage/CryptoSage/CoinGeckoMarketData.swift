//
//  CoinGeckoMarketData.swift
//  CryptoSage
//
//  Created by ChatGPT on 05/24/25
//

import Foundation

/// Represents one coin record returned by CoinGecko’s `/coins/markets` endpoint.
struct CoinGeckoMarketData: Decodable, Identifiable {
    let id: String
    let symbol: String
    let name: String
    let image: String
    let currentPrice: Double
    let totalVolume: Double
    let marketCap: Double
    let priceChangePercentage24H: Double?
    let priceChangePercentage1HInCurrency: Double?
    let sparklineIn7D: SparklineData?

    private enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case name
        case image
        case currentPrice                = "current_price"
        case totalVolume                 = "total_volume"
        case marketCap                   = "market_cap"
        case priceChangePercentage24H    = "price_change_percentage_24h"
        case priceChangePercentage1HInCurrency = "price_change_percentage_1h_in_currency"
        case sparklineIn7D               = "sparkline_in_7d"
    }
}

/// Nested type for decoding the 7-day sparkline price array.
struct SparklineData: Codable {
    let price: [Double]
}
