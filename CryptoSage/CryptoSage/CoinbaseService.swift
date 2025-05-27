//
//  CoinbaseService.swift
//  CSAI1
//
//  Created by DM on 3/21/25.
//  Updated with improved error handling, retry logic, coin pair filtering, session reuse,
//  and caching for invalid coin pair logging.
//

import Foundation

struct CoinbaseSpotPriceResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let base: String
        let currency: String
        let amount: String
    }
}

actor CoinbaseService {
    private let validPairs: Set<String> = [
        "BTC-USD","ETH-USD","USDT-USD","XRP-USD","BNB-USD",
        "USDC-USD","SOL-USD","DOGE-USD","ADA-USD","TRX-USD",
        "WBTC-USD","WETH-USD","WEETH-USD","UNI-USD","DAI-USD",
        "APT-USD","TON-USD","LINK-USD","XLM-USD","WSTETH-USD",
        "AVAX-USD","SUI-USD","SHIB-USD","HBAR-USD","LTC-USD",
        "OM-USD","DOT-USD","BCH-USD","SUSDE-USD","AAVE-USD",
        "ATOM-USD","CRO-USD","NEAR-USD","PEPE-USD","OKB-USD",
        "CBBTC-USD","GT-USD"
    ]
    private var invalidPairsLogged: Set<String> = []

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    func fetchSpotPrice(
        coin: String = "BTC",
        fiat: String = "USD",
        maxRetries: Int = 3,
        allowUnlistedPairs: Bool = false
    ) async -> Double? {
        let pair = "\(coin.uppercased())-\(fiat.uppercased())"
        if !allowUnlistedPairs && !validPairs.contains(pair) {
            invalidPairsLogged.insert(pair)
            return nil
        }
        guard let url = URL(string: "https://api.coinbase.com/v2/prices/\(pair)/spot") else {
            return nil
        }

        var attempt = 0
        while attempt < maxRetries {
            attempt += 1
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    if http.statusCode == 400 || http.statusCode == 404 {
                        return nil
                    }
                }
                let resp = try JSONDecoder().decode(CoinbaseSpotPriceResponse.self, from: data)
                guard let field = resp.data,
                      let price = Double(field.amount) else {
                    return nil
                }
                return price
            } catch {
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
                } else {
                    return nil
                }
            }
        }
        return nil
    }
}
