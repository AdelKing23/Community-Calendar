import SwiftUI
import UIKit

struct ListingRemoteImageView<Placeholder: View>: View {
    let image: EventImage?
    let context: String
    let contentMode: ContentMode
    @ViewBuilder let placeholder: Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                placeholder
                    .overlay {
                        ProgressView()
                            .tint(PCCTheme.pohutukawaOrange)
                    }
            } else {
                placeholder
                    .overlay {
                        if loadFailed {
                            Image(systemName: "photo")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(PCCTheme.pohutukawaRed.opacity(0.58))
                        }
                    }
            }
        }
        .task(id: image?.signedURL) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let image else {
            loadedImage = nil
            isLoading = false
            loadFailed = false
            return
        }

        guard let signedURL = image.signedURL,
              signedURL.scheme != nil,
              signedURL.host != nil else {
            loadedImage = nil
            isLoading = false
            loadFailed = true
            debug("missing signed URL, image=\(image.redactedID)")
            return
        }

        isLoading = true
        loadFailed = false

        do {
            let (data, response) = try await URLSession.shared.data(from: signedURL)

            guard let httpResponse = response as? HTTPURLResponse else {
                loadedImage = nil
                isLoading = false
                loadFailed = true
                debug("GET invalid response, image=\(image.redactedID)")
                return
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil"

            guard (200..<300).contains(httpResponse.statusCode),
                  let rendered = UIImage(data: data) else {
                loadedImage = nil
                isLoading = false
                loadFailed = true
                debug("GET failed status=\(httpResponse.statusCode), content_type=\(contentType), bytes=\(data.count), image=\(image.redactedID)")
                return
            }

            loadedImage = rendered
            isLoading = false
        } catch {
            loadedImage = nil
            isLoading = false
            loadFailed = true
            debug("GET error=\(error.localizedDescription), image=\(image.redactedID)")
        }
    }

    private func debug(_ message: String) {
        #if DEBUG
        print("[ListingImage] \(context): \(message)")
        #endif
    }
}

private extension EventImage {
    var redactedID: String {
        String(id.uuidString.prefix(8))
    }
}
