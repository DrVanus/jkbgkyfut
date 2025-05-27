//
//  CryptoNewsArticle.swift
//  CryptoSage
//
//  Created by DM on 5/26/25.
//


//
// CryptoNewsArticle.swift
// CryptoSage
//

import Foundation

/// Represents a single news article in the CryptoSage app.
struct CryptoNewsArticle: Codable, Identifiable {
    /// Unique identifier for SwiftUI lists
    let id: UUID
    
    /// Headline of the article
    let title: String
    
    /// Optional subtitle or summary
    let description: String?
    
    /// Link to the full article
    let url: URL
    
    /// Optional URL to an image
    let imageUrl: URL?
    
    /// Publication date
    let publishedAt: Date
    
    /// Provides a default UUID when decoding or initializing
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        url: URL,
        imageUrl: URL? = nil,
        publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.imageUrl = imageUrl
        self.publishedAt = publishedAt
    }
}