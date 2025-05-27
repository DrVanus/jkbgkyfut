import SwiftUI
import Foundation

struct MarketView: View {
    @StateObject private var marketVM = MarketViewModel.shared

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Global market summary at the top
                    // Global market summary view
                    if let global = marketVM.globalData {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading) {
                                Text("Total Market Cap")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                                Text((global.totalMarketCap["usd"] ?? 0).formattedWithAbbreviations())
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                Text("24h Volume")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                                Text((global.totalVolume["usd"] ?? 0).formattedWithAbbreviations())
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                Text("BTC Dominance")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                                Text(String(format: "%.1f%%", (global.marketCapPercentage["btc"] ?? 0)))
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    // Segmented filter row & search toggle
                    segmentRow

                    // Search bar
                    if marketVM.showSearchBar {
                        TextField("Search coins...", text: $marketVM.searchText)
                            .foregroundColor(.white)
                            .onChange(of: marketVM.searchText) { _ in
                                marketVM.applyAllFiltersAndSort()
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Table column headers
                    columnHeader

                    // Content
                    if marketVM.filteredCoins.isEmpty && marketVM.isLoadingCoins {
                        loadingView
                    } else if marketVM.filteredCoins.isEmpty {
                        emptyOrErrorView
                    } else {
                        coinList
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            await marketVM.loadAllData()
        }
    }

    // MARK: - Subviews

    private var segmentRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MarketSegment.allCases, id: \.self) { seg in
                        Button {
                            marketVM.updateSegment(seg)
                        } label: {
                            Text(seg.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(marketVM.selectedSegment == seg ? .black : .white)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(marketVM.selectedSegment == seg ? Color.white : Color.white.opacity(0.1))
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            Button {
                withAnimation { marketVM.showSearchBar.toggle() }
            } label: {
                Image(systemName: marketVM.showSearchBar ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(.trailing, 16)
            }
        }
        .background(Color.black)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            headerButton("Coin", .coin)
                .frame(width: 140, alignment: .leading)
            Text("7D")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 40, alignment: .trailing)
            headerButton("Price", .price)
                .frame(width: 70, alignment: .trailing)
            headerButton("24h", .dailyChange)
                .frame(width: 50, alignment: .trailing)
            headerButton("Vol", .volume)
                .frame(width: 70, alignment: .trailing)
            Text("Fav")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 40, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
    }

    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shows either an error view with retry button or a placeholder text.
    private var emptyOrErrorView: AnyView {
        if let error = marketVM.coinError {
            return AnyView(
                DataUnavailableView(message: error) {
                    Task {
                        do {
                            try await marketVM.loadAllData()
                        } catch {
                            marketVM.coinError = "Could not load market data: \(error.localizedDescription)"
                        }
                    }
                }
            )
        } else {
            return AnyView(
                Text(marketVM.searchText.isEmpty ? "No coins available." : "No coins match your search.")
                    .foregroundColor(.gray)
                    .padding(.top, 40)
            )
        }
    }

    private var coinList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(marketVM.filteredCoins) { coin in
                    NavigationLink(destination: CoinDetailView(coin: coin)) {
                        CoinRowView(coin: coin)
                            .transition(.opacity)
                            .environmentObject(marketVM)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 16)
                }
            }
            .padding(.bottom, 12)
        }
        .refreshable {
            await marketVM.loadAllData()
        }
    }

    // MARK: - Helpers

    private func headerButton(_ label: String, _ field: SortField) -> some View {
        Button {
            marketVM.toggleSort(for: field)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                if marketVM.sortField == field {
                    Image(systemName: marketVM.sortDirection == .asc ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(marketVM.sortField == field ? Color.white.opacity(0.05) : Color.clear)
    }
}

#if DEBUG
struct MarketView_Previews: PreviewProvider {
    static var marketVM = MarketViewModel.shared
    static var previews: some View {
        MarketView()
            .environmentObject(marketVM)
    }
}
#endif

// Restore volume formatting helper
extension Double {
    func formattedWithAbbreviations() -> String {
        let absValue = abs(self)
        switch absValue {
        case 1_000_000_000_000...:
            return String(format: "%.1fT", self / 1_000_000_000_000)
        case 1_000_000_000...:
            return String(format: "%.1fB", self / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", self / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", self / 1_000)
        default:
            return String(format: "%.0f", self)
        }
    }
}
