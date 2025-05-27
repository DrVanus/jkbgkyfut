//
//  MarketSegment.swift
//  CSAI1
//
//  Created by DM on 4/1/25.
//

import SwiftUI
import Foundation
import Combine
// Uses shared GlobalDataResponse & GlobalMarketData models

/// Which slice of the market to display.
enum MarketSegment: String, CaseIterable {
    case all       = "All"
    case trending  = "Trending"
    case gainers   = "Gainers"
    case losers    = "Losers"
    case favorites = "Favorites"
}

/// Fields by which to sort.
enum SortField: String, CaseIterable {
    case coin
    case price
    case dailyChange
    case volume
    case marketCap
}

/// Ascending or descending sort direction.
enum SortDirection {
    case asc, desc
}





// MARK: - Helper for Explicit Async Timeouts

func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }
        guard let result = try await group.next() else {
            throw URLError(.timedOut)
        }
        group.cancelAll()
        return result
    }
}

// MARK: - MarketSegmentViewModel

@MainActor
class MarketSegmentViewModel: ObservableObject {
    @Published var coins: [MarketCoin] = []
    @Published var filteredCoins: [MarketCoin] = []
    @Published var globalData: GlobalMarketData?
    @Published var isLoading: Bool = false
    
    @Published var selectedSegment: MarketSegment = .all
    @Published var showSearchBar: Bool = false
    @Published var searchText: String = ""
    
    @Published var sortField: SortField = .marketCap
    @Published var sortDirection: SortDirection = .desc
    
    @Published var coinError: String?
    @Published var globalError: String?
    
    private let favoritesKey = "favoriteCoinSymbols"
    private var coinRefreshTask: Task<Void, Never>?
    private var globalRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    private let pinnedCoins = ["BTC", "ETH", "BNB", "XRP", "ADA", "DOGE", "MATIC", "SOL", "DOT", "LTC", "SHIB", "TRX", "AVAX", "LINK", "UNI", "BCH"]
    
    init() {
        if let cached = MarketCacheManager.shared.loadCoinsFromDisk() {
            self.coins = cached
        } else {
            loadFallbackCoins()
        }
        self.coins.sort { $0.marketCap > $1.marketCap }
        loadFavorites()
        applyAllFiltersAndSort()
        
        Task {
            await fetchMarketDataMulti()
            await fetchGlobalMarketDataMulti()
        }
        
        startAutoRefresh()
    }
    
    deinit {
        coinRefreshTask?.cancel()
        globalRefreshTask?.cancel()
    }

    /// Initialize by subscribing to a shared MarketViewModel’s coin list
    convenience init(marketVM: MarketViewModel) {
        self.init()
        marketVM.$coins
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coins in
                self?.coins = coins
                self?.applyAllFiltersAndSort()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Fetching Coin Data
    
    private func fetchCoinGecko() async throws -> [CoinGeckoMarketData] {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        
        return try await withThrowingTaskGroup(of: [CoinGeckoMarketData].self) { group in
            for page in 1...3 {
                group.addTask {
                    let urlString = """
                    https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd\
                    &order=market_cap_desc&per_page=100&page=\(page)&sparkline=true\
                    &price_change_percentage=1h,24h
                    """
                    guard let url = URL(string: urlString) else { throw URLError(.badURL) }
                    let data = try await withTimeout(seconds: 15) {
                        let (d, response) = try await session.data(from: url)
                        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                            throw URLError(.badServerResponse)
                        }
                        return d
                    }
                    return try JSONDecoder().decode([CoinGeckoMarketData].self, from: data)
                }
            }
            var allCoins: [CoinGeckoMarketData] = []
            for try await pageCoins in group {
                allCoins.append(contentsOf: pageCoins)
            }
            return allCoins
        }
    }
    
    private func fetchCoinGeckoWithRetry(retries: Int = 1) async throws -> [CoinGeckoMarketData] {
        var lastError: Error?
        for attempt in 0...retries {
            do {
                return try await fetchCoinGecko()
            } catch {
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }
    
    private func fetchCoinPaprika() async throws -> [CoinPaprikaData] {
        let urlString = "https://api.coinpaprika.com/v1/tickers?quotes=USD&limit=100"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        
        let (data, response) = try await session.data(from: url)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([CoinPaprikaData].self, from: data)
    }
    
    func fetchMarketDataMulti() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let geckoCoins = try await fetchCoinGeckoWithRetry(retries: 1)
            var updatedCoins = geckoCoins.map { raw in
                MarketCoin(
                    id: raw.id,
                    symbol: raw.symbol.uppercased(),
                    name: raw.name,
                    imageUrl: URL(string: raw.image),
                    finalImageUrl: nil,
                    price: raw.currentPrice,
                    dailyChange: raw.priceChangePercentage24H ?? 0,
                    volume: raw.totalVolume,
                    marketCap: raw.marketCap,
                    isFavorite: false
                )
            }
            updatedCoins = updatedCoins.filter { coin in
                let nameLC = coin.name.lowercased()
                return !(nameLC.contains("binance-peg") || nameLC.contains("bridged") || nameLC.contains("wormhole"))
            }
            var seenSymbols = Set<String>()
            updatedCoins = updatedCoins.filter { coin in
                let (inserted, _) = seenSymbols.insert(coin.symbol)
                return inserted
            }
            MarketCacheManager.shared.saveCoinsToDisk(updatedCoins)
            self.coins = updatedCoins
            
            if searchText.isEmpty && selectedSegment == .all && sortField == .marketCap && sortDirection == .desc {
                let pinnedCoinsList = coins.filter { pinnedCoins.contains($0.symbol) }
                let otherCoins = coins.filter { !pinnedCoins.contains($0.symbol) }
                self.coins = pinnedCoinsList.sorted { (a, b) in
                    let idxA = pinnedCoins.firstIndex(of: a.symbol) ?? Int.max
                    let idxB = pinnedCoins.firstIndex(of: b.symbol) ?? Int.max
                    return idxA < idxB
                } + otherCoins.sorted { $0.marketCap > $1.marketCap }
            } else {
                self.coins.sort { $0.marketCap > $1.marketCap }
            }
            
            coinError = nil
        } catch {
            do {
                let papCoins = try await fetchCoinPaprika()
                var updated: [MarketCoin] = []
                for pap in papCoins {
                    let price    = pap.quotes?["USD"]?.price ?? 0
                    let vol      = pap.quotes?["USD"]?.volume_24h ?? 0
                    let change24 = pap.quotes?["USD"]?.percent_change_24h ?? 0
                    let newCoin = MarketCoin(
                        id: pap.id,
                        symbol: pap.symbol.uppercased(),
                        name: pap.name,
                        imageUrl: nil,
                        finalImageUrl: nil,
                        price: price,
                        dailyChange: change24,
                        volume: vol,
                        marketCap: pap.quotes?["USD"]?.market_cap ?? 0,
                        isFavorite: false
                    )
                    updated.append(newCoin)
                }
                updated = updated.filter {
                    let nameLC = $0.name.lowercased()
                    return !(nameLC.contains("binance-peg") || nameLC.contains("bridged") || nameLC.contains("wormhole"))
                }
                var seen = Set<String>()
                updated = updated.filter {
                    let (inserted, _) = seen.insert($0.symbol)
                    return inserted
                }
                MarketCacheManager.shared.saveCoinsToDisk(updated)
                self.coins = updated.sorted { $0.marketCap > $1.marketCap }
                coinError = nil
            } catch {
                coinError = "Failed to load market data. Please try again later."
            }
        }
        loadFavorites()
        applyAllFiltersAndSort()
    }
    
    // MARK: - Fetching Global Data
    
    private func fetchGlobalCoinGecko() async throws -> GlobalMarketData {
        let urlString = "https://api.coingecko.com/api/v3/global"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        let (data, response) = try await session.data(from: url)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(GlobalDataResponse.self, from: data)
        return decoded.data
    }
    
    private func fetchGlobalPaprika() async throws -> GlobalMarketData {
        let urlString = "https://api.coinpaprika.com/v1/global"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        let (data, response) = try await session.data(from: url)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GlobalMarketData.self, from: data)
    }
    
    func fetchGlobalMarketDataMulti() async {
        do {
            let gData = try await fetchGlobalCoinGecko()
            self.globalData = gData
            globalError = nil
        } catch {
            do {
                let fallback = try await fetchGlobalPaprika()
                self.globalData = fallback
                globalError = "Using fallback aggregator for global data."
            } catch {
                globalError = "Global data error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Fallback Local Data
    
    private func loadFallbackCoins() {
        self.coins = [
            MarketCoin(
                id: "BTC",
                symbol: "BTC",
                name: "Bitcoin",
                imageUrl: URL(string: "https://www.cryptocompare.com/media/19633/btc.png"),
                finalImageUrl: nil,
                price: 28_000,
                dailyChange: -2.15,
                volume: 450_000_000,
                marketCap: 500_000_000_000,
                isFavorite: false
            ),
            MarketCoin(
                id: "ETH",
                symbol: "ETH",
                name: "Ethereum",
                imageUrl: URL(string: "https://www.cryptocompare.com/media/20646/eth.png"),
                finalImageUrl: nil,
                price: 1_800,
                dailyChange: 3.44,
                volume: 210_000_000,
                marketCap: 200_000_000_000,
                isFavorite: false
            )
        ]
    }
    
    // MARK: - Favorites
    
    private func loadFavorites() {
        let saved = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        for i in coins.indices {
            if saved.contains(coins[i].symbol.uppercased()) {
                coins[i].isFavorite = true
            }
        }
    }
    
    private func saveFavorites() {
        let faves = coins.filter { $0.isFavorite }.map { $0.symbol.uppercased() }
        UserDefaults.standard.setValue(faves, forKey: favoritesKey)
    }
    
    func toggleFavorite(_ coin: MarketCoin) {
        guard let idx = coins.firstIndex(where: { $0.id == coin.id }) else { return }
        withAnimation(.spring()) {
            coins[idx].isFavorite.toggle()
        }
        saveFavorites()
        applyAllFiltersAndSort()
    }
    
    // MARK: - Sorting & Filtering
    
    @MainActor
    func updateSegment(_ seg: MarketSegment) {
        selectedSegment = seg
        applyAllFiltersAndSort()
    }
    
    @MainActor
    func updateSearch(_ query: String) {
        searchText = query
        applyAllFiltersAndSort()
    }
    
    func toggleSort(for field: SortField) {
        if sortField == field {
            sortDirection = (sortDirection == .asc) ? .desc : .asc
        } else {
            sortField = field
            sortDirection = .asc
        }
        applyAllFiltersAndSort()
    }
    
    func applyAllFiltersAndSort() {
        var result = coins
        
        let lowerSearch = searchText.lowercased()
        if !lowerSearch.isEmpty {
            result = result.filter {
                $0.symbol.lowercased().contains(lowerSearch) ||
                $0.name.lowercased().contains(lowerSearch)
            }
        }
        
        switch selectedSegment {
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .gainers:
            result = result.filter { $0.dailyChange > 0 }
        case .losers:
            result = result.filter { $0.dailyChange < 0 }
        default:
            break
        }
        
        withAnimation {
            filteredCoins = sortCoins(result)
        }
    }
    
    private func sortCoins(_ arr: [MarketCoin]) -> [MarketCoin] {
        if searchText.isEmpty && selectedSegment == .all && sortField == .marketCap && sortDirection == .desc {
            let pinnedList = arr.filter { pinnedCoins.contains($0.symbol) }
            let nonPinned = arr.filter { !pinnedCoins.contains($0.symbol) }
            let sortedPinned = pinnedList.sorted {
                let idx0 = pinnedCoins.firstIndex(of: $0.symbol) ?? Int.max
                let idx1 = pinnedCoins.firstIndex(of: $1.symbol) ?? Int.max
                return idx0 < idx1
            }
            let sortedOthers = nonPinned.sorted { $0.marketCap > $1.marketCap }
            return sortedPinned + sortedOthers
        } else {
            return arr.sorted(by: { lhs, rhs in
                switch sortField {
                case .coin:
                    let compare = lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol)
                    return sortDirection == .asc ? (compare == .orderedAscending) : (compare == .orderedDescending)
                case .price:
                    return sortDirection == .asc ? (lhs.price < rhs.price) : (lhs.price > rhs.price)
                case .dailyChange:
                    return sortDirection == .asc ? (lhs.dailyChange < rhs.dailyChange) : (lhs.dailyChange > rhs.dailyChange)
                case .volume:
                    return sortDirection == .asc
                        ? (lhs.totalVolume < rhs.totalVolume)
                        : (lhs.totalVolume > rhs.totalVolume)
                case .marketCap:
                    return sortDirection == .asc ? (lhs.marketCap < rhs.marketCap) : (lhs.marketCap > rhs.marketCap)
                }
            })
        }
    }
    
    // MARK: - Auto-Refresh
    
    private func startAutoRefresh() {
        coinRefreshTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self.fetchMarketDataMulti()
            }
        }
        
        globalRefreshTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                await self.fetchGlobalMarketDataMulti()
            }
        }
    }
    
    // MARK: - Optional: Live Prices from Coinbase/Binance
    
    func fetchLivePricesFromCoinbase() {
        let currentCoins = coins
        Task {
            var updates: [(symbol: String, newPrice: Double, newSpark: [Double])] = []
            for coin in currentCoins {
                if let newPrice = await CoinbaseService().fetchSpotPrice(coin: coin.symbol, fiat: "USD") {
                    let newSpark = await BinanceService.fetchSparkline(symbol: coin.symbol)
                    updates.append((symbol: coin.symbol, newPrice: newPrice, newSpark: newSpark))
                }
            }
            
            await MainActor.run {
                for update in updates {
                    if let idx = coins.firstIndex(where: { $0.symbol == update.symbol }) {
                        coins[idx].currentPrice = update.newPrice
                        if !update.newSpark.isEmpty {
                            coins[idx].sparkline7d = SparklineIn7D(price: update.newSpark)
                        }
                    }
                }
                applyAllFiltersAndSort()
            }
        }
    }
}
