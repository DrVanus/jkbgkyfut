//
//  CoinRowView.swift
//  CryptoSage
//
//  Created by DM on 5/25/25.
//


import SwiftUI

/// A reusable row view for displaying a single coin in a list.
struct CoinRowView: View {
    let coin: MarketCoin
    @EnvironmentObject var marketVM: MarketViewModel

    // Constants for layout
    private let starWidth: CGFloat = 40
    private let priceWidth: CGFloat = 70
    private let volumeWidth: CGFloat = 70

    var body: some View {
        HStack(spacing: 12) {
            // Coin icon
            CoinImageView(symbol: coin.symbol, urlStr: coin.image, size: 32)
                .frame(width: 32, height: 32)

            // Symbol + name
            VStack(alignment: .leading, spacing: 2) {
                Text(coin.symbol.uppercased())
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(coin.name)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            // Sparkline
            if let prices = coin.sparkline7d?.price, prices.count > 1 {
                SparklineView(
                    data: prices,
                    isPositive: (coin.priceChangePercentage24hInCurrency ?? 0) >= 0
                )
                .frame(width: 40)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 30)
            }

            // Price + change
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", coin.currentPrice))
                    .font(.subheadline)
                    .foregroundColor(.white)
                let change24h = coin.priceChangePercentage24hInCurrency ?? 0
                Text(String(format: "%.2f%%", change24h))
                    .font(.caption)
                    .foregroundColor(change24h >= 0 ? .green : .red)
                    .animation(.easeInOut, value: change24h)
            }
            .frame(width: priceWidth)

            // Volume
            Text(coin.totalVolume.formattedWithAbbreviations())
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: volumeWidth, alignment: .trailing)

            // Favorite toggle
            Button {
                marketVM.toggleFavorite(coin)
            } label: {
                Image(systemName: marketVM.isFavorite(coin) ? "star.fill" : "star")
                    .foregroundColor(marketVM.isFavorite(coin) ? .yellow : .white.opacity(0.6))
                    .frame(width: starWidth, alignment: .center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 60)
    }
}

// MARK: - Previews and Sample Data

extension MarketCoin {
    static var sample: MarketCoin {
        MarketCoin(
            id: "bitcoin",
            symbol: "btc",
            name: "Bitcoin",
            image: "https://assets.coingecko.com/coins/images/1/large/bitcoin.png",
            price: 50000,
            dailyChange: 2.0,
            volume: 35_000_000_000,
            marketCap: 900_000_000_000,
            isFavorite: true
        )
    }
}

#if DEBUG
struct CoinRowView_Previews: PreviewProvider {
    static var previews: some View {
        CoinRowView(coin: .sample)
            .environmentObject(MarketViewModel.shared)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.black)
    }
}
#endif
