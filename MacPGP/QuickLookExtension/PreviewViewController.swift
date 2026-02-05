import Cocoa
import Quartz
import SwiftUI
import ObjectivePGP

class PreviewViewController: NSViewController, QLPreviewingController {

    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfSearchableItem(identifier: String, queryString: String?, completionHandler handler: @escaping (Error?) -> Void) {
        handler(nil)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Check if this is a PGP file
        let fileExtension = url.pathExtension.lowercased()
        guard ["gpg", "pgp", "asc"].contains(fileExtension) else {
            handler(NSError(domain: "com.macpgp.quicklook", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a PGP file"]))
            return
        }

        // Extract metadata from the encrypted file
        let extractor = PGPMetadataExtractor()

        do {
            let metadata = try extractor.extractMetadata(from: url)

            // Create SwiftUI view with metadata
            let previewView = EncryptionMetadataView(metadata: metadata, fileURL: url)
            let hostingController = NSHostingController(rootView: previewView)

            // Set up the view hierarchy
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            handler(nil)
        } catch {
            // If metadata extraction fails, show error
            let errorView = EncryptionErrorView(error: error, fileURL: url)
            let hostingController = NSHostingController(rootView: errorView)

            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            handler(nil)
        }
    }
}

// MARK: - SwiftUI Views

struct EncryptionMetadataView: View {
    let metadata: PGPMetadataExtractor.Metadata
    let fileURL: URL

    @State private var showPassphrasePrompt = false
    @State private var passphrase = ""
    @State private var decryptedData: Data?
    @State private var decryptionError: String?
    @State private var isDecrypting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: decryptedData != nil ? "lock.open.fill" : "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(decryptedData != nil ? .green : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(decryptedData != nil ? "Decrypted Content" : "PGP Encrypted File")
                        .font(.headline)
                    Text(fileURL.lastPathComponent)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content area - show decrypted content or metadata
            if let decryptedData = decryptedData {
                DecryptedContentView(data: decryptedData, filename: metadata.filename)
            } else {
                metadataContentView
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .overlay(
            Group {
                if showPassphrasePrompt {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showPassphrasePrompt = false
                            passphrase = ""
                            decryptionError = nil
                        }

                    PassphrasePromptView(
                        passphrase: $passphrase,
                        isPresented: $showPassphrasePrompt,
                        onDecrypt: { enteredPassphrase in
                            handleDecryption(passphrase: enteredPassphrase)
                        }
                    )
                    .overlay(
                        Group {
                            if isDecrypting {
                                VStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Decrypting...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else if let error = decryptionError {
                                VStack(spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.top, 8)
                            }
                        }
                        .offset(y: 100)
                    )
                }
            }
        )
    }

    private var metadataContentView: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Encryption Information
                    MetadataSection(title: "Encryption Information") {
                        if let algorithm = metadata.encryptionAlgorithm {
                            MetadataRow(label: "Algorithm", value: algorithm.description)
                        }

                        MetadataRow(
                            label: "Integrity Protection",
                            value: metadata.isIntegrityProtected ? "Yes (MDC)" : "No"
                        )

                        if let compression = metadata.compressionAlgorithm {
                            MetadataRow(label: "Compression", value: compression)
                        }
                    }

                    // Recipients
                    MetadataSection(title: "Recipients") {
                        if metadata.recipientKeyIDs.isEmpty {
                            Text("No recipient information available")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            ForEach(metadata.recipientKeyIDs, id: \.self) { keyID in
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.blue)
                                    Text(formatKeyID(keyID))
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }

                    // File Information
                    MetadataSection(title: "File Information") {
                        MetadataRow(label: "File Size", value: formatFileSize(metadata.fileSize))

                        if let filename = metadata.filename {
                            MetadataRow(label: "Original Name", value: filename)
                        }

                        if let creationDate = metadata.creationDate {
                            MetadataRow(label: "Created", value: formatDate(creationDate))
                        }
                    }

                    // Decrypt button
                    Button {
                        showPassphrasePrompt = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.open.fill")
                            Text("Decrypt Preview")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding()
        }
    }

    private func handleDecryption(passphrase: String) {
        isDecrypting = true
        decryptionError = nil

        Task {
            do {
                // Load the encrypted file data
                let encryptedData = try Data(contentsOf: fileURL)

                // Load keys from shared keyring directory
                let keys = try loadKeysFromKeyring()
                let secretKeys = keys.filter { $0.isSecret }

                guard !secretKeys.isEmpty else {
                    await MainActor.run {
                        isDecrypting = false
                        decryptionError = "No secret keys found. Import a key in the main app first."
                    }
                    return
                }

                // Try to decrypt with each secret key
                var lastError: Error?
                for key in secretKeys {
                    do {
                        let decrypted = try ObjectivePGP.decrypt(
                            encryptedData,
                            andVerifySignature: false,
                            using: [key],
                            passphraseForKey: { _ in passphrase }
                        )

                        // Successfully decrypted!
                        await MainActor.run {
                            self.decryptedData = decrypted
                            self.showPassphrasePrompt = false
                            self.passphrase = ""
                            self.isDecrypting = false
                            self.decryptionError = nil
                        }
                        return
                    } catch {
                        lastError = error
                        // Try next key
                        continue
                    }
                }

                // If we get here, none of the keys worked
                let nsError = lastError as? NSError
                let errorMessage: String
                if nsError?.domain == "ObjectivePGP" && nsError?.code == 2 {
                    errorMessage = "Invalid passphrase. Please try again."
                } else {
                    errorMessage = "Unable to decrypt. Check your passphrase and keys."
                }

                await MainActor.run {
                    isDecrypting = false
                    decryptionError = errorMessage
                }

            } catch {
                await MainActor.run {
                    isDecrypting = false
                    decryptionError = "Decryption failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadKeysFromKeyring() throws -> [Key] {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let keyringDir = appSupport.appendingPathComponent("MacPGP/Keyring", isDirectory: true)

        let publicKeyringPath = keyringDir.appendingPathComponent("pubring.gpg")
        let secretKeyringPath = keyringDir.appendingPathComponent("secring.gpg")

        var keys: [Key] = []

        if fileManager.fileExists(atPath: publicKeyringPath.path) {
            let publicKeys = try ObjectivePGP.readKeys(fromPath: publicKeyringPath.path)
            keys.append(contentsOf: publicKeys)
        }

        if fileManager.fileExists(atPath: secretKeyringPath.path) {
            let secretKeys = try ObjectivePGP.readKeys(fromPath: secretKeyringPath.path)
            for secretKey in secretKeys {
                if let index = keys.firstIndex(where: { $0.publicKey?.fingerprint == secretKey.publicKey?.fingerprint }) {
                    keys[index] = secretKey
                } else {
                    keys.append(secretKey)
                }
            }
        }

        return keys
    }

    private func formatKeyID(_ keyID: String) -> String {
        // Format key ID as: XXXX XXXX XXXX XXXX
        let chunks = stride(from: 0, to: keyID.count, by: 4).map {
            String(keyID.dropFirst($0).prefix(4))
        }
        return chunks.joined(separator: " ")
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct MetadataSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(.leading, 8)
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

struct DecryptedContentView: View {
    let data: Data
    let filename: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Try to display as text first
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    TextContentView(text: text)
                }
                // Try to display as image
                else if let nsImage = NSImage(data: data) {
                    ImageContentView(image: nsImage, filename: filename)
                }
                // Show raw data info if cannot display
                else {
                    BinaryContentView(dataSize: data.count, filename: filename)
                }
            }
            .padding()
        }
    }
}

struct TextContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("Text Content")
                    .font(.headline)
                Spacer()
            }

            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ImageContentView: View {
    let image: NSImage
    let filename: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.fill")
                    .foregroundColor(.blue)
                Text("Image Content")
                    .font(.headline)
                if let filename = filename {
                    Text("(\(filename))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 600, maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct BinaryContentView: View {
    let dataSize: Int
    let filename: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Binary Content")
                .font(.headline)

            if let filename = filename {
                Text(filename)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(dataSize), countStyle: .file))")
                .font(.body)
                .foregroundColor(.secondary)

            Text("This file contains binary data that cannot be previewed as text or image.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EncryptionErrorView: View {
    let error: Error
    let fileURL: URL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Unable to Read Encrypted File")
                .font(.headline)

            Text(fileURL.lastPathComponent)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(minWidth: 400, minHeight: 300)
        .padding()
    }
}
