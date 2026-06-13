import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CryptoMultipleFileInputSection: View {
    let title: String
    @Binding var selectedFiles: [URL]
    let outputLocation: URL?
    let onChooseOutputLocation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CryptoFileSelectionSection(title: title, selectedFiles: $selectedFiles)

            CryptoOutputLocationSection(
                location: outputLocation,
                onChooseOutputLocation: onChooseOutputLocation
            )
        }
    }
}

struct CryptoSingleFileInputSection: View {
    let title: String
    @Binding var selectedFile: URL?
    var selectedFileIcon = "doc.fill"
    var usesBorderlessRemoveButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if let selectedFile {
                CryptoSelectedFileRow(
                    file: selectedFile,
                    iconName: selectedFileIcon,
                    usesBorderlessRemoveButton: usesBorderlessRemoveButton
                ) {
                    self.selectedFile = nil
                }
            } else {
                DropZone(fileURL: $selectedFile)
            }
        }
    }
}

private struct CryptoFileSelectionSection: View {
    let title: String
    @Binding var selectedFiles: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if !selectedFiles.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(selectedFiles.enumerated()), id: \.offset) { index, file in
                        CryptoSelectedFileRow(
                            file: file,
                            iconName: "doc.fill",
                            usesBorderlessRemoveButton: true
                        ) {
                            selectedFiles.remove(at: index)
                        }
                    }
                }
            } else {
                DropZone(fileURLs: $selectedFiles)
            }
        }
    }
}

private struct CryptoOutputLocationSection: View {
    let location: URL?
    let onChooseOutputLocation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Location")
                .font(.headline)

            if let location {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    Text(location.path)
                        .lineLimit(1)
                        .font(.caption)
                    Spacer()
                    Button("Change", action: onChooseOutputLocation)
                        .buttonStyle(.borderless)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Button(action: onChooseOutputLocation) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Choose Output Location")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct CryptoSelectedFileRow: View {
    let file: URL
    let iconName: String
    let usesBorderlessRemoveButton: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            Text(file.lastPathComponent)
                .lineLimit(1)
            Spacer()
            removeButton
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var removeButton: some View {
        if usesBorderlessRemoveButton {
            Button("Remove", action: onRemove)
                .buttonStyle(.borderless)
        } else {
            Button("Remove", action: onRemove)
        }
    }
}

struct DropZone: View {
    private var multipleFiles: Binding<[URL]>?
    private var singleFile: Binding<URL?>?
    private var allowsMultiple: Bool

    @State private var isTargeted = false

    init(fileURLs: Binding<[URL]>) {
        self.multipleFiles = fileURLs
        self.singleFile = nil
        self.allowsMultiple = true
    }

    init(fileURL: Binding<URL?>) {
        self.multipleFiles = nil
        self.singleFile = fileURL
        self.allowsMultiple = false
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(allowsMultiple ? "Drop files here" : "Drop a file here")
                .font(.headline)

            Text("or")
                .foregroundStyle(.secondary)

            Button(allowsMultiple ? "Select Files..." : "Select File...") {
                selectFiles()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .foregroundStyle(isTargeted ? .blue : .secondary.opacity(0.5))
        )
        .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard !providers.isEmpty else { return false }

            if allowsMultiple {
                let loadedURLs = DroppedFileURLStore()
                let group = DispatchGroup()

                for (index, provider) in providers.enumerated() {
                    group.enter()
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            loadedURLs.set(url, at: index)
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    self.multipleFiles?.wrappedValue.append(contentsOf: loadedURLs.snapshot())
                }
            } else {
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.singleFile?.wrappedValue = url
                        }
                    }
                }
            }

            return true
        }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            if allowsMultiple {
                multipleFiles?.wrappedValue.append(contentsOf: panel.urls)
            } else {
                singleFile?.wrappedValue = panel.url
            }
        }
    }
}

final class DroppedFileURLStore: @unchecked Sendable {
    private let lock = NSLock()
    private var urlsByProviderIndex: [Int: URL] = [:]

    func set(_ url: URL, at providerIndex: Int) {
        lock.lock()
        defer { lock.unlock() }

        urlsByProviderIndex[providerIndex] = url
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        return urlsByProviderIndex.keys.sorted().compactMap { urlsByProviderIndex[$0] }
    }
}
