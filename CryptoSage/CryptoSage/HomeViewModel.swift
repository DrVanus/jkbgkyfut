//
//  HomeViewModel.swift
//  CSAI1
//
//  ViewModel to provide data for Home screen: portfolio, news, heatmap, market overview.
//

import Foundation
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Child ViewModels
    @Published var portfolioVM = PortfolioViewModel()
    @Published var newsVM      = CryptoNewsFeedViewModel()
    @Published var heatMapVM   = HeatMapViewModel()

    // Published market slices for UI sections
    @Published var liveTrending: [MarketCoin] = []
    @Published var liveTopGainers: [MarketCoin] = []
    @Published var liveTopLosers: [MarketCoin] = []

    // Shared Market ViewModel (injected at creation)
    let marketVM: MarketViewModel

    init() {
        self.marketVM = MarketViewModel.shared
        // Load market data on startup
        Task {
            await fetchMarketData()
            await newsVM.loadPreviewNews()
        }
    }

    init(marketVM: MarketViewModel) {
        self.marketVM = marketVM
        // Load market data on startup
        Task {
            await fetchMarketData()
            await newsVM.loadPreviewNews()
        }
    }

    // MARK: - Market Data Fetching
    /// Fetches the full coin list once, then updates our three @Published slices.
    func fetchMarketData() async {
        await marketVM.loadAllData()
        liveTrending   = marketVM.trendingCoins
        liveTopGainers = marketVM.topGainers
        liveTopLosers  = marketVM.topLosers
    }

    /// Convenience wrappers forwarding to fetchMarketData()
    func fetchTrending()    { Task { await fetchMarketData() } }
    func fetchTopGainers()  { Task { await fetchMarketData() } }
    func fetchTopLosers()   { Task { await fetchMarketData() } }

    /// Heatmap data (tiles & weights)
    var heatMapTiles: [HeatMapTile] {
        heatMapVM.tiles
    }
    var heatMapWeights: [Double] {
        heatMapVM.weights()
    }
}
