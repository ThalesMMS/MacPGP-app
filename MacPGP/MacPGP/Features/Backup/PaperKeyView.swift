import SwiftUI

struct PaperKeyView: View {
    let key: PGPKeyModel
    @Environment(KeyringService.self) private var keyringService
    @State private var armoredKey: String = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showQRCode = false
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with title and actions
            HStack {
                Text("Paper Key Backup")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if !isLoading && loadError == nil {
                    Button {
                        printPaperBackup()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading key...")
                    Spacer()
                }
                .padding()
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)

                    Text("Failed to load key")
                        .font(.headline)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Key information section
                        keyInformationSection

                        Divider()

                        // Armored key section
                        armoredKeySection

                        // QR code section (only for keys < 2KB)
                        if shouldShowQRCode {
                            Divider()
                            qrCodeSection
                        }

                        // Warning section
                        warningSection
                    }
                    .padding()
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadArmoredKey()
        }
    }

    // MARK: - Key Information Section

    @ViewBuilder
    private var keyInformationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Information")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "User ID", value: key.primaryUserID?.displayString ?? "Unknown")

                if let email = key.email {
                    infoRow(label: "Email", value: email)
                }

                infoRow(label: "Key Type", value: key.keyTypeDescription)
                infoRow(label: "Algorithm", value: key.algorithmDescription)
                infoRow(label: "Created", value: formatDate(key.creationDate))

                if let expirationDate = key.expirationDate {
                    infoRow(label: "Expires", value: formatDate(expirationDate))
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Fingerprint
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fingerprint")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Button {
                        copyFingerprint()
                    } label: {
                        Label(showCopied ? "Copied!" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                Text(key.formattedFingerprint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Armored Key Section

    @ViewBuilder
    private var armoredKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Private Key (ASCII Armored)")
                    .font(.headline)

                Spacer()

                Button {
                    copyArmoredKey()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(armoredKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - QR Code Section

    @ViewBuilder
    private var qrCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QR Code")
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation {
                        showQRCode.toggle()
                    }
                } label: {
                    Label(showQRCode ? "Hide" : "Show", systemImage: showQRCode ? "eye.slash" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if showQRCode {
                VStack(spacing: 12) {
                    QRCodeView(armoredKey, size: 300)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 2)

                    Text("Scan to import this key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    // MARK: - Warning Section

    @ViewBuilder
    private var warningSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Important Security Notice")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("This paper backup contains your private key. Store it securely in a safe place. Anyone with access to this paper can decrypt your messages and sign documents as you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    // MARK: - Computed Properties

    private var shouldShowQRCode: Bool {
        let keySize = armoredKey.utf8.count
        return keySize < 2048 // 2KB limit for QR code
    }

    // MARK: - Helper Methods

    private func loadArmoredKey() {
        isLoading = true
        loadError = nil

        do {
            let keyData = try keyringService.exportKey(key, includeSecretKey: true, armored: true)

            if let armoredString = String(data: keyData, encoding: .utf8) {
                armoredKey = armoredString
            } else {
                throw NSError(domain: "PaperKeyView", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to convert key data to string"
                ])
            }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyFingerprint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key.fingerprint, forType: .string)

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }

    private func copyArmoredKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(armoredKey, forType: .string)
    }

    private func printPaperBackup() {
        let printInfo = NSPrintInfo.shared
        printInfo.orientation = .portrait
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let printOperation = NSPrintOperation(view: createPrintView(), printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true

        if let window = NSApplication.shared.keyWindow {
            printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    private func createPrintView() -> NSView {
        let view = NSHostingView(rootView: printableContent)
        view.frame = NSRect(x: 0, y: 0, width: 612, height: 792) // Letter size in points
        return view
    }

    @ViewBuilder
    private var printableContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PGP Key Paper Backup")
                .font(.title)
                .fontWeight(.bold)

            Divider()

            keyInformationSection

            Divider()

            armoredKeySection

            if shouldShowQRCode {
                Divider()

                VStack(spacing: 12) {
                    Text("QR Code")
                        .font(.headline)

                    QRCodeView(armoredKey, size: 250)
                        .padding()
                        .background(Color.white)
                }
            }

            Divider()

            warningSection

            Spacer()

            Text("Generated on \(formatDate(Date()))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    PaperKeyView(key: .preview)
        .environment(KeyringService())
}
