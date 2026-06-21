import Foundation
import UniformTypeIdentifiers

nonisolated enum ShareItemFileLoader {
    private static let fileURLTypeIdentifier = UTType.fileURL.identifier
    private static let fallbackTypeIdentifiers = [
        UTType.item.identifier,
        UTType.content.identifier,
        UTType.data.identifier
    ]

    static func fileURLs(from inputItems: [NSExtensionItem]) async -> [URL] {
        var fileURLs: [URL] = []

        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if let url = await fileURL(from: provider) {
                    fileURLs.append(url)
                }
            }
        }

        return fileURLs
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(fileURLTypeIdentifier),
           let url = await directFileURL(from: provider) {
            return url
        }

        if let url = await fileRepresentation(from: provider) {
            return url
        }

        return await dataRepresentation(from: provider)
    }

    private static func directFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: fileURLTypeIdentifier, options: nil) { item, error in
                if let error {
                    NSLog("ShareItemFileLoader: Failed to load file URL: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: url(from: item))
            }
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        return nil
    }

    private static func fileRepresentation(from provider: NSItemProvider) async -> URL? {
        for typeIdentifier in candidateTypeIdentifiers(for: provider) {
            if let url = await loadFileRepresentation(from: provider, typeIdentifier: typeIdentifier) {
                return url
            }
        }

        return nil
    }

    private static func loadFileRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    NSLog("ShareItemFileLoader: Failed to load file representation for \(typeIdentifier): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: copyTemporaryFile(
                        at: url,
                        suggestedName: suggestedName,
                        typeIdentifier: typeIdentifier
                    )
                )
            }
        }
    }

    private static func dataRepresentation(from provider: NSItemProvider) async -> URL? {
        for typeIdentifier in candidateTypeIdentifiers(for: provider) {
            if let url = await loadDataRepresentation(from: provider, typeIdentifier: typeIdentifier) {
                return url
            }
        }

        return nil
    }

    private static func loadDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    NSLog("ShareItemFileLoader: Failed to load data representation for \(typeIdentifier): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: writeTemporaryFile(
                        data,
                        suggestedName: suggestedName,
                        typeIdentifier: typeIdentifier
                    )
                )
            }
        }
    }

    private static func candidateTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        var identifiers = provider.registeredTypeIdentifiers

        for fallback in fallbackTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(fallback) {
            if !identifiers.contains(fallback) {
                identifiers.append(fallback)
            }
        }

        return identifiers
    }

    private static func copyTemporaryFile(at url: URL, suggestedName: String?, typeIdentifier: String) -> URL? {
        do {
            let destination = try temporaryFileURL(
                suggestedName: suggestedName ?? url.lastPathComponent,
                typeIdentifier: typeIdentifier
            )
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            NSLog("ShareItemFileLoader: Failed to copy file representation: \(error.localizedDescription)")
            return nil
        }
    }

    private static func writeTemporaryFile(_ data: Data, suggestedName: String?, typeIdentifier: String) -> URL? {
        do {
            let destination = try temporaryFileURL(suggestedName: suggestedName, typeIdentifier: typeIdentifier)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            NSLog("ShareItemFileLoader: Failed to write data representation: \(error.localizedDescription)")
            return nil
        }
    }

    private static func temporaryFileURL(suggestedName: String?, typeIdentifier: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPGP-ShareItemFileLoader", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var fileName = sanitizedFileName(suggestedName)
        if URL(fileURLWithPath: fileName).pathExtension.isEmpty,
           let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension {
            fileName += ".\(fileExtension)"
        }

        return directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    }

    private static func sanitizedFileName(_ suggestedName: String?) -> String {
        let fallback = "shared-item"
        let trimmedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName: String
        if let trimmedName, !trimmedName.isEmpty {
            rawName = trimmedName
        } else {
            rawName = fallback
        }

        let lastPathComponent = URL(fileURLWithPath: rawName).lastPathComponent
        return lastPathComponent.isEmpty ? fallback : lastPathComponent
    }
}
