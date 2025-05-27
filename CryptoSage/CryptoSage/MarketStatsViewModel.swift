//
//  MarketStatsViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/20/25.
//

import Foundation

/// Represents a single stat for display.
public struct Stat: Identifiable {
    public let id = UUID()
    public let title: String
    public let value: String
    public let iconName: String
}

@MainActor
public class MarketStatsViewModel: ObservableObject {
    @Published public private(set) var stats: [Stat] = []

    public init() {
        Task { await fetchStats() }
    }

    /// Fetches global market stats from CoinGecko’s global endpoint.
    public func fetchStats() async {
        print("▶️ fetchStats() called")
        // Temporary dummy data to verify UI rendering
        let dummy: [Stat] = [
            Stat(title: "Market Cap",  value: "$1.20T", iconName: "globe"),
            Stat(title: "24h Volume",  value: "$85.3B", iconName: "clock"),
            Stat(title: "BTC Dom",     value: "46.75%", iconName: "bitcoinsign.circle.fill"),
            Stat(title: "ETH Dom",     value: "19.20%", iconName: "chart.bar.fill"),
            Stat(title: "24h Volatility", value: "3.45%", iconName: "waveform.path.ecg"),
            Stat(title: "24h Change",  value: "+2.15%", iconName: "arrow.up.arrow.down.circle")
        ]
        await MainActor.run {
            self.stats = dummy
            print("✅ Dummy stats loaded with \(dummy.count) items")
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ v: Double) -> String {
        switch v {
        case 1_000_000_000_000...: return String(format: "$%.2fT", v/1_000_000_000_000)
        case 1_000_000_000...: return String(format: "$%.2fB", v/1_000_000_000)
        case 1_000_000...: return String(format: "$%.2fM", v/1_000_000)
        default:
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
            return f.string(from: v as NSNumber) ?? "$\(v)"
        }
    }

    private func formatNumber(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: v as NSNumber) ?? "\(v)"
    }
}

/// JSON wrapper for CoinGecko global endpoint
private struct GlobalMarketDataWrapper: Decodable {
    let data: GlobalMarketData
}
