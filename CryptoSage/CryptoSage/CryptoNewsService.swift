//
//  NewsAPIResponse 2.swift
//  CryptoSage
//
//  Created by DM on 5/26/25.
//


//
// CryptoNewsService.swift
// CryptoSage
//

import Foundation

// MARK: - NewsAPI Models
struct NewsAPIResponse: Codable {
    let articles: [NewsAPIArticle]
}

struct NewsAPIArticle: Codable {
    let title: String
    let description: String?
    let url: URL
    let urlToImage: URL?
    let publishedAt: Date
}

// MARK: - CryptoNews Service
actor CryptoNewsService {
    private let apiKey = "fe1702f65ad54c4aa51b209b54f8ba3f"

    /// Fetch a small preview of news (for the home screen)
    func fetchPreviewNews() async -> [CryptoNewsArticle] {
        await fetchNews(pageSize: 5)
    }

    /// Fetch the latest full list of news
    func fetchLatestNews() async -> [CryptoNewsArticle] {
        await fetchNews(pageSize: 20)
    }

    /// Internal helper to call NewsAPI
    private func fetchNews(pageSize: Int) async -> [CryptoNewsArticle] {
        guard var components = URLComponents(string: "https://newsapi.org/v2/everything") else {
            return []
        }
        components.queryItems = [
            .init(name: "q", value: "crypto"),
            .init(name: "pageSize", value: "\(pageSize)"),
            .init(name: "sortBy", value: "publishedAt"),
            .init(name: "apiKey", value: apiKey)
        ]
        guard let url = components.url else {
            print("🗞️ CryptoNewsService: failed to construct URL from components")
            return []
        }
        // Build a request with a timeout
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            print("🗞️ CryptoNewsService: fetching news from URL:", url)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                print("🗞️ CryptoNewsService: HTTP error code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let apiResponse = try decoder.decode(NewsAPIResponse.self, from: data)
            return apiResponse.articles.map { article in
                CryptoNewsArticle(
                    title: article.title,
                    description: article.description,
                    url: article.url,
                    imageUrl: article.urlToImage,
                    publishedAt: article.publishedAt
                )
            }
        } catch {
            print("🗞️ CryptoNewsService error:", error)
            return []
        }
    }
}
