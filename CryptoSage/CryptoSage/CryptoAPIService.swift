import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private(set) var isOnline: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = (path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
}

private extension FileManager {
    static func cacheURL(for fileName: String) -> URL {
        let docs = Self.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }
}

private func saveCache(data: Data, to fileName: String) {
    let url = FileManager.cacheURL(for: fileName)
    try? data.write(to: url)
}

private func loadCache<T: Decodable>(from fileName: String, as type: T.Type) -> T? {
    let url = FileManager.cacheURL(for: fileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

final class CryptoAPIService {
    static let shared = CryptoAPIService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// Fetches global market data from the CoinGecko `/global` endpoint.
    func fetchGlobalData() async throws -> GlobalMarketData {
        guard NetworkMonitor.shared.isOnline else {
            if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                print("📥 fetchGlobalData: loaded from cache")
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        print("▶️ fetchGlobalData() called")
        let url = URL(string: "https://api.coingecko.com/api/v3/global")!
        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                let (data, response) = try await session.data(from: url)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📡 fetchGlobalData JSON:", jsonString)
                }
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let wrapper = try decoder.decode(GlobalDataResponse.self, from: data)
                saveCache(data: data, to: "global_cache.json")
                return wrapper.data
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                // exponential backoff: 0.5s, 1s, 2s...
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                // on last failed retry, try loading from cache
                if attempts >= 2,
                   let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                    print("📥 fetchGlobalData: network error, loaded from cache")
                    return cached
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    func fetchCoinMarkets() async throws -> [MarketCoin] {
        guard NetworkMonitor.shared.isOnline else {
            if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                print("📥 fetchCoinMarkets: loaded from cache")
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h")
        ]
        let url = components.url!
        print("▶️ fetchCoinMarkets() →", url)

        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                let (data, response) = try await session.data(from: url)
                print("✅ fetchCoinMarkets: received \(data.count) bytes from \(url)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📥 fetchCoinMarkets JSON:", jsonString)
                }
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                saveCache(data: data, to: "coins_cache.json")
                return try decoder.decode([MarketCoin].self, from: data)
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                // exponential backoff: 0.5s, 1s, 2s...
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                // on last failed retry, try loading from cache
                if attempts >= 2,
                   let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    print("📥 fetchCoinMarkets: network error, loaded from cache")
                    return cached
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    func fetchWatchlistMarkets(ids: [String]) async throws -> [MarketCoin] {
        guard NetworkMonitor.shared.isOnline else {
            if var cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                cached = cached.filter { ids.contains($0.id) }
                print("📥 fetchWatchlistMarkets: loaded from cache")
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        guard !ids.isEmpty else { return [] }
        let idList = ids.joined(separator: ",")
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: idList),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h")
        ]
        let url = components.url!
        print("▶️ fetchWatchlistMarkets() →", url)

        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                let (data, response) = try await session.data(from: url)
                print("✅ fetchWatchlistMarkets: received \(data.count) bytes from \(url)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📥 fetchWatchlistMarkets JSON:", jsonString)
                }
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                saveCache(data: data, to: "coins_cache.json")
                return try decoder.decode([MarketCoin].self, from: data)
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                // exponential backoff: 0.5s, 1s, 2s...
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                // on last failed retry, try loading from cache
                if attempts >= 2,
                   let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    let filtered = cached.filter { ids.contains($0.id) }
                    print("📥 fetchWatchlistMarkets: network error, loaded from cache")
                    return filtered
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // Add other purely data‐focused API methods below.
}
