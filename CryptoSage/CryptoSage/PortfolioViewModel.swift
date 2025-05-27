import SwiftUI
import Combine

// MARK: - Chart Data Model
struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

class PortfolioViewModel: ObservableObject {
    // MARK: - Persistence URL
    private let transactionsFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("transactions.json")
    }()
    
    init() {
        loadHoldings()
        loadTransactions()
        loadHistory()       // ← Add this line
        startAutoRefresh()
    }
    
    // MARK: - Published Properties
    @Published var holdings: [Holding] = []
    @Published var history: [ChartPoint] = []
    @Published var highlightedDate: Date? = nil
    @Published var transactions: [Transaction] = []
    @Published var editingTransaction: Transaction? = nil

    // Computed property for total portfolio value.
    var totalValue: Double {
        holdings.reduce(0) { $0 + $1.currentValue }
    }
    
    // MARK: - Data Loading and Auto-Refresh
    
    /// Loads sample holdings data. Replace this with your data fetching logic.
    func loadHoldings() {
        holdings = [
            Holding(
                coinName: "Bitcoin",
                coinSymbol: "BTC",
                quantity: 1,
                currentPrice: 35000,
                costBasis: 20000,
                imageUrl: nil,
                isFavorite: true,
                dailyChange: 2.1,
                purchaseDate: Date()
            ),
            Holding(
                coinName: "Ethereum",
                coinSymbol: "ETH",
                quantity: 10,
                currentPrice: 1800,
                costBasis: 15000,
                imageUrl: nil,
                isFavorite: false,
                dailyChange: -1.2,
                purchaseDate: Date()
            ),
            Holding(
                coinName: "Solana",
                coinSymbol: "SOL",
                quantity: 100,
                currentPrice: 20,
                costBasis: 2000,
                imageUrl: nil,
                isFavorite: false,
                dailyChange: 3.5,
                purchaseDate: Date()
            )
        ]
    }
    
    // Timer to auto-refresh data periodically.
    private var timer: Timer?
    
    /// Starts a timer to refresh portfolio data every 60 seconds.
    func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task {
                await self.refreshPortfolioData()
            }
        }
    }
    
    /// Stops the auto-refresh timer.
    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Refreshes portfolio data. Replace with your network request or logic as needed.
    func refreshPortfolioData() async {
        // Replace sample data with live data fetched from 3Commas.
        await MainActor.run {
            fetchHoldingsFrom3Commas()
            loadHistory()   // ← Add this line
        }
    }
    
    // MARK: - NEW: Fetch Holdings from 3Commas
    
    /// Fetches holdings from 3Commas API and updates the holdings array.
    func fetchHoldingsFrom3Commas() {
        Task {
            do {
                // 1) List all 3Commas accounts
                let accounts = try await ThreeCommasService.shared.listAccounts()

                // 2) Fetch balances for each account and convert to Holding
                var newHoldings: [Holding] = []
                for account in accounts {
                    let balances = try await ThreeCommasService.shared.loadAccountBalances(accountId: account.id)
                    // Find the balance entry matching the account's currency
                    if let entry = balances.first(where: { $0.currency == account.currency }) {
                        let holding = Holding(
                            coinName: account.name ?? (account.currency ?? ""),
                            coinSymbol: account.currency ?? "",
                            quantity: entry.balance,
                            currentPrice: 0.0,   // Replace with real price lookup if available
                            costBasis: 0.0,      // Replace with real cost basis logic if available
                            imageUrl: nil,
                            isFavorite: false,
                            dailyChange: 0.0,
                            purchaseDate: Date()
                        )
                        newHoldings.append(holding)
                    }
                }

                let snapshot = newHoldings
                await MainActor.run {
                    self.holdings = snapshot
                }
            } catch {
                print("Error fetching 3Commas holdings:", error)
            }
        }
    }
    
    // MARK: - Transaction and Holding Management
    
    /// Removes a holding at the given index set.
    func removeHolding(at indexSet: IndexSet) {
        holdings.remove(atOffsets: indexSet)
    }
    
    // Removed the old version of deleteManualTransaction(_:)
    
    // MARK: - NEW: Add a Holding
    
    /// Creates and appends a new Holding to the array, matching what AddHoldingView calls.
    func addHolding(
        coinName: String,
        coinSymbol: String,
        quantity: Double,
        currentPrice: Double,
        costBasis: Double,
        imageUrl: String?,
        purchaseDate: Date
    ) {
        let newHolding = Holding(
            coinName: coinName,
            coinSymbol: coinSymbol,
            quantity: quantity,
            currentPrice: currentPrice,
            costBasis: costBasis,
            imageUrl: imageUrl,
            isFavorite: false,    // default to not-favorite
            dailyChange: 0.0,     // or fetch real data if available
            purchaseDate: purchaseDate
        )
        
        holdings.append(newHolding)
    }
    
    // MARK: - NEW: Toggle Favorite
    
    /// Toggles the isFavorite flag on a specific holding.
    func toggleFavorite(_ holding: Holding) {
        guard let index = holdings.firstIndex(where: { $0.id == holding.id }) else { return }
        holdings[index].isFavorite.toggle()
    }
}

// MARK: - Transaction & Portfolio Management
extension PortfolioViewModel {
    /// Adds a transaction and updates the corresponding holding.
    func addTransaction(_ transaction: Transaction) {
        transactions.append(transaction)
        updateHolding(with: transaction)
        saveTransactions()
    }
    
    /// Updates or creates a holding based on a transaction.
    private func updateHolding(with transaction: Transaction) {
        // Try to find an existing holding by coin symbol (case-insensitive).
        if let index = holdings.firstIndex(where: { $0.coinSymbol.uppercased() == transaction.coinSymbol.uppercased() }) {
            var holding = holdings[index]
            
            if transaction.isBuy {
                // For a buy, calculate the new total cost and quantity, then update the average cost basis.
                let currentTotalCost = holding.costBasis * holding.quantity
                let transactionCost = transaction.pricePerUnit * transaction.quantity
                let newQuantity = holding.quantity + transaction.quantity
                let newCostBasis = newQuantity > 0 ? (currentTotalCost + transactionCost) / newQuantity : 0
                
                holding.quantity = newQuantity
                holding.costBasis = newCostBasis
            } else {
                // For a sell, subtract the sold quantity from the holding.
                holding.quantity -= transaction.quantity
                // If holding.quantity <= 0, consider removing it or resetting cost basis.
            }
            
            holdings[index] = holding
        } else {
            // No existing holding found.
            if transaction.isBuy {
                // Create a new holding for a buy transaction.
                let newHolding = Holding(
                    // We don't have transaction.coinName, so reuse coinSymbol as coinName for now.
                    coinName: transaction.coinSymbol,
                    coinSymbol: transaction.coinSymbol,
                    quantity: transaction.quantity,
                    currentPrice: transaction.pricePerUnit,  // Placeholder; update as needed
                    costBasis: transaction.pricePerUnit,
                    imageUrl: nil,
                    isFavorite: false,
                    dailyChange: 0.0,
                    purchaseDate: transaction.date
                )
                holdings.append(newHolding)
            } else {
                // Correctly formatted error message:
                print("Error: Trying to sell a coin that doesn't exist in holdings.")
            }
        }
    }
}

// MARK: - Transaction Editing & Recalculation
extension PortfolioViewModel {
    /// Recalculates holdings from all transactions.
    private func recalcHoldingsFromAllTransactions() {
        // Clear current holdings
        holdings.removeAll()
        
        // Optional: Sort transactions by date if order matters
        let sortedTransactions = transactions.sorted { $0.date < $1.date }
        
        // Reapply each transaction
        for tx in sortedTransactions {
            updateHolding(with: tx)
        }
    }
    
    /// Updates an existing manual transaction.
    func updateTransaction(oldTx: Transaction, newTx: Transaction) {
        // Only allow editing of manual transactions
        guard oldTx.isManual else {
            print("Error: Cannot update an exchange transaction.")
            return
        }
        
        if let index = transactions.firstIndex(where: { $0.id == oldTx.id }) {
            transactions[index] = newTx
        } else {
            print("Error: Transaction not found.")
        }
        
        recalcHoldingsFromAllTransactions()
        saveTransactions()
    }
    
    /// Deletes a manual transaction and recalculates holdings.
    func deleteManualTransaction(_ tx: Transaction) {
        // Only allow deletion of manual transactions
        guard tx.isManual else {
            print("Error: Cannot delete an exchange transaction.")
            return
        }
        
        if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
            transactions.remove(at: index)
        } else {
            print("Error: Transaction not found.")
        }
        
        recalcHoldingsFromAllTransactions()
        saveTransactions()
    }
}

// MARK: - Persistence
extension PortfolioViewModel {
    /// Loads saved transactions from disk.
    private func loadTransactions() {
        do {
            let data = try Data(contentsOf: transactionsFileURL)
            let decoded = try JSONDecoder().decode([Transaction].self, from: data)
            self.transactions = decoded
        } catch {
            print("Failed to load transactions:", error)
        }
    }

    /// Saves current transactions to disk.
    private func saveTransactions() {
        do {
            let data = try JSONEncoder().encode(transactions)
            try data.write(to: transactionsFileURL, options: [.atomic])
        } catch {
            print("Failed to save transactions:", error)
        }
    }
    
    /// Builds a time-series of portfolio total value for the past 30 days.
    func loadHistory() {
        var points: [ChartPoint] = []
        for daysAgo in stride(from: 30, through: 0, by: -1) {
            if let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) {
                let valueAtDate = totalValue  // TODO: Replace with real historical lookup if available
                points.append(ChartPoint(date: date, value: valueAtDate))
            }
        }
        history = points
    }
}
