import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(KeyringService.self) private var keyringService
    @State private var selectedSidebarItem: SidebarItem? = .keyring
    @State private var selectedKey: PGPKeyModel?
    @State private var showingKeyGeneration = false
    @State private var showingImportSheet = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var needsDetailColumn: Bool {
        selectedSidebarItem == .keyring
    }

    var body: some View {
        Group {
            if needsDetailColumn {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(selection: $selectedSidebarItem)
                } content: {
                    KeyringView(selectedKey: $selectedKey)
                } detail: {
                    detailView
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selectedSidebarItem)
                } detail: {
                    contentView
                }
                .navigationSplitViewStyle(.prominentDetail)
            }
        }
        .sheet(isPresented: $showingKeyGeneration) {
            KeyGenerationView()
        }
        .fileImporter(
            isPresented: $showingImportSheet,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyGeneration)) { _ in
            showingKeyGeneration = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importKey)) { _ in
            showingImportSheet = true
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedSidebarItem {
        case .encrypt:
            EncryptView()
        case .decrypt:
            DecryptView()
        case .sign:
            SignView()
        case .verify:
            VerifyView()
        case .keyring, nil:
            Text("Select an item")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let key = selectedKey {
            KeyDetailsView(key: key)
        } else {
            ContentUnavailableView(
                "No Key Selected",
                systemImage: "key",
                description: Text("Select a key to view its details")
            )
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let importedKeys = try keyringService.importKey(from: url)
                    if let firstKey = importedKeys.first {
                        selectedKey = firstKey
                    }
                } catch {
                    print("Import failed: \(error)")
                }
            }
        case .failure(let error):
            print("File selection failed: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .environment(KeyringService())
}
