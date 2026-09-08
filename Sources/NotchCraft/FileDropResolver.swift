import Foundation
import UniformTypeIdentifiers

enum FileDropResolver {
    private static let maxInlineImportedDataBytes = 32 * 1024 * 1024

    static var supportedDropTypeIdentifiers: [String] {
        Array(Set([UTType.fileURL.identifier] + preferredImageTypes.map(\.identifier)))
    }

    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) -> Bool {
        let supportedProviders = providers.filter {
            supportsFileURL($0) || preferredImageType(for: $0) != nil
        }

        guard !supportedProviders.isEmpty else {
            return false
        }

        let group = DispatchGroup()
        let buffer = URLBuffer()

        for provider in supportedProviders {
            group.enter()
            loadURL(from: provider) { url in
                defer { group.leave() }

                guard let url else {
                    return
                }

                buffer.append(url.standardizedFileURL)
            }
        }

        group.notify(queue: .main) {
            let uniqueURLs = buffer.snapshot().reduce(into: [URL]()) { result, url in
                if !result.contains(url.standardizedFileURL) {
                    result.append(url.standardizedFileURL)
                }
            }

            completion(uniqueURLs)
        }

        return true
    }

    private static func supportsFileURL(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    private static func preferredImageType(for provider: NSItemProvider) -> UTType? {
        preferredImageTypes.first { type in
            provider.hasItemConformingToTypeIdentifier(type.identifier)
        }
    }

    private static func loadURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        let callback = MainThreadURLCallback(completion)

        if supportsFileURL(provider) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                callback.call(url(from: item))
            }
            return
        }

        guard let imageType = preferredImageType(for: provider) else {
            callback.call(nil)
            return
        }

        let suggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: imageType.identifier) { url, _ in
            if let url,
               let importedURL = TrayManagedStorage.importDroppedFile(url, suggestedName: suggestedName) {
                callback.call(importedURL)
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                guard let data,
                      data.count <= Self.maxInlineImportedDataBytes
                else {
                    callback.call(nil)
                    return
                }

                let storedURL = TrayManagedStorage.storeDroppedData(data, type: imageType, suggestedName: suggestedName)
                callback.call(storedURL)
            }
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let url = item as? URL {
            return url
        }

        if let nsURL = item as? NSURL {
            return nsURL as URL
        }

        if let string = item as? String, let url = URL(string: string), url.isFileURL {
            return url
        }

        return nil
    }

    private static let preferredImageTypes: [UTType] = [
        .png,
        .jpeg,
        .heic,
        .tiff,
        .gif,
        .bmp,
        .image
    ]
}

private final class URLBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

private final class MainThreadURLCallback: @unchecked Sendable {
    private let completion: (URL?) -> Void

    init(_ completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func call(_ url: URL?) {
        DispatchQueue.main.async {
            self.completion(url)
        }
    }
}
