import SwiftUI
import UIKit

@main
struct CryptoSageAIApp: App {
    @StateObject private var appState: AppState
    @StateObject private var marketVM: MarketViewModel
    @StateObject private var portfolioVM: PortfolioViewModel
    @StateObject private var newsVM: CryptoNewsFeedViewModel
    @StateObject private var segmentVM: MarketSegmentViewModel

    init() {
        let appState = AppState()
        let marketVM = MarketViewModel.shared
        _appState = StateObject(wrappedValue: appState)
        _marketVM = StateObject(wrappedValue: marketVM)
        _portfolioVM = StateObject(wrappedValue: PortfolioViewModel())
        _newsVM = StateObject(wrappedValue: CryptoNewsFeedViewModel())
        _segmentVM = StateObject(wrappedValue: MarketSegmentViewModel())
        // Global navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.black
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ZStack {
                    Group {
                        switch appState.selectedTab {
                        case .home:
                            HomeView()
                        case .market:
                            MarketView()
                        case .trade:
                            TradeView()
                        case .portfolio:
                            PortfolioView()
                        case .ai:
                            AITabView()
                        }
                    }

                    VStack {
                        Spacer()
                        CustomTabBar(selectedTab: $appState.selectedTab)
                    }
                }
            }
            .environmentObject(appState)
            .environmentObject(marketVM)
            .environmentObject(portfolioVM)
            .environmentObject(newsVM)
            .environmentObject(segmentVM)
            .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        }
    }
}

class AppState: ObservableObject {
    @Published var selectedTab: CustomTab = .home
    @Published var isDarkMode: Bool = true
}
