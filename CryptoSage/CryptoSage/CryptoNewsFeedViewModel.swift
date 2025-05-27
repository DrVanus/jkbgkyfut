import SwiftUI
import Foundation

@MainActor
final class CryptoNewsFeedViewModel: ObservableObject {
    @Published var articles: [CryptoNewsArticle] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let newsService = CryptoNewsService()

    init() {
        Task { await loadPreviewNews() }
    }

    @MainActor
    func loadPreviewNews() async {
        isLoading = true
        let fetchedArticles = await newsService.fetchPreviewNews()
        articles = fetchedArticles
        // Show error message if no articles
        if fetchedArticles.isEmpty {
            errorMessage = "No news available"
        } else {
            errorMessage = nil
        }
        isLoading = false
    }

    // Track read/bookmarked articles
    @Published private var readArticleIDs: Set<UUID> = []
    @Published private var bookmarkedArticleIDs: Set<UUID> = []

    // MARK: - Read / Bookmark Actions

    func toggleRead(_ article: CryptoNewsArticle) {
        if isRead(article) {
            readArticleIDs.remove(article.id)
        } else {
            readArticleIDs.insert(article.id)
        }
    }

    func isRead(_ article: CryptoNewsArticle) -> Bool {
        readArticleIDs.contains(article.id)
    }

    func toggleBookmark(_ article: CryptoNewsArticle) {
        if isBookmarked(article) {
            bookmarkedArticleIDs.remove(article.id)
        } else {
            bookmarkedArticleIDs.insert(article.id)
        }
    }

    func isBookmarked(_ article: CryptoNewsArticle) -> Bool {
        bookmarkedArticleIDs.contains(article.id)
    }
}
