import SwiftUI

struct AllCryptoNewsView: View {
    @StateObject private var vm = CryptoNewsFeedViewModel()

    var body: some View {
        VStack {
            // 1) Loading state
            if vm.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // 2) Error state
            else if let error = vm.errorMessage {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task {
                            await vm.loadPreviewNews()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
            // 3) Success state
            else {
                List(vm.articles) { article in
                    NavigationLink(destination: NewsWebView(url: article.url)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.title).font(.headline)
                            Text(article.publishedAt, style: .relative)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
                .refreshable {
                    await vm.loadPreviewNews()
                }
            }
        }
        .navigationTitle("Crypto News")
        .onAppear {
            Task {
                await vm.loadPreviewNews()
            }
        }
        .accentColor(.white)
    }
}

struct AllCryptoNewsView_Previews: PreviewProvider {
    static var previews: some View {
        AllCryptoNewsView()
    }
}
