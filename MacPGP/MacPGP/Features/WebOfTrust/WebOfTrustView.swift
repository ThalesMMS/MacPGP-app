import SwiftUI

@Observable
class WebOfTrustViewModel {
    private let trustService: TrustService
    private let keyringService: KeyringService

    var selectedNode: TrustNode?
    var nodes: [TrustNode] = []
    var edges: [TrustEdge] = []
    var filterType: TrustFilterType = .all
    var showingAlert = false
    var alertMessage: String?

    init(trustService: TrustService, keyringService: KeyringService) {
        self.trustService = trustService
        self.keyringService = keyringService
        loadGraph()
    }

    func loadGraph() {
        let keys = keyringService.keys

        // Build nodes from all keys
        nodes = keys.map { key in
            TrustNode(
                id: key.fingerprint,
                key: key,
                trustLevel: key.trustLevel
            )
        }

        // Build graph using trust service
        let graph = trustService.buildTrustGraph()
        edges = graph.edges

        // Apply filter
        applyFilter()
    }

    func applyFilter() {
        switch filterType {
        case .all:
            // Show all nodes and edges
            break
        case .trustedOnly:
            // Filter to show only nodes with trust level >= marginal
            let trustedFingerprints = Set(nodes
                .filter { $0.trustLevel.trustValue >= TrustLevel.marginal.trustValue }
                .map { $0.id })

            edges = edges.filter { edge in
                trustedFingerprints.contains(edge.from) && trustedFingerprints.contains(edge.to)
            }
        case .secretKeysOnly:
            // Show only secret keys and their direct relationships
            let secretKeyFingerprints = Set(nodes
                .filter { $0.key.isSecretKey }
                .map { $0.id })

            edges = edges.filter { edge in
                secretKeyFingerprints.contains(edge.from) || secretKeyFingerprints.contains(edge.to)
            }
        }
    }

    func selectNode(_ node: TrustNode?) {
        selectedNode = node
    }

    func showKeyDetails(for node: TrustNode) {
        // Post notification to show key details
        NotificationCenter.default.post(
            name: .showKeyDetails,
            object: nil,
            userInfo: ["key": node.key]
        )
    }
}

enum TrustFilterType: String, CaseIterable, Identifiable {
    case all = "All Keys"
    case trustedOnly = "Trusted Only"
    case secretKeysOnly = "Secret Keys"

    var id: String { rawValue }
}

struct WebOfTrustView: View {
    @Environment(TrustService.self) private var trustService
    @Environment(KeyringService.self) private var keyringService
    @State private var viewModel: WebOfTrustViewModel?
    @State private var showingLegend = false

    var body: some View {
        Group {
            if let viewModel = viewModel {
                graphContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = WebOfTrustViewModel(
                    trustService: trustService,
                    keyringService: keyringService
                )
            }
        }
        .navigationTitle("Web of Trust")
    }

    @ViewBuilder
    private func graphContent(viewModel: WebOfTrustViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            toolbar(viewModel: viewModel)

            if viewModel.nodes.isEmpty {
                emptyStateView()
            } else {
                graphView(viewModel: viewModel)
            }
        }
        .alert("Error", isPresented: $vm.showingAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.alertMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingLegend) {
            legendView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .keysReloaded)) { _ in
            viewModel.loadGraph()
        }
    }

    @ViewBuilder
    private func toolbar(viewModel: WebOfTrustViewModel) -> some View {
        @Bindable var vm = viewModel

        HStack {
            Picker("Filter", selection: $vm.filterType) {
                ForEach(TrustFilterType.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
            .onChange(of: viewModel.filterType) { _, _ in
                viewModel.applyFilter()
            }

            Spacer()

            Button {
                showingLegend.toggle()
            } label: {
                Label("Legend", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderless)

            Button {
                viewModel.loadGraph()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func emptyStateView() -> some View {
        ContentUnavailableView {
            Label("No Keys", systemImage: "network")
        } description: {
            Text("Generate or import keys to build your web of trust.")
        } actions: {
            Button("Generate New Key") {
                NotificationCenter.default.post(name: .showKeyGeneration, object: nil)
            }
            .buttonStyle(.borderedProminent)

            Button("Import Key") {
                NotificationCenter.default.post(name: .importKey, object: nil)
            }
        }
    }

    @ViewBuilder
    private func graphView(viewModel: WebOfTrustViewModel) -> some View {
        ZStack(alignment: .bottomTrailing) {
            TrustGraphView(
                nodes: viewModel.nodes,
                edges: viewModel.edges,
                selectedNode: viewModel.selectedNode,
                onNodeSelected: { node in
                    viewModel.selectNode(node)
                }
            )

            // Selection info overlay
            if let selectedNode = viewModel.selectedNode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected: \(selectedNode.key.displayName)")
                                .font(.headline)
                            Text("Trust Level: \(selectedNode.trustLevel.displayName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if selectedNode.key.isSecretKey {
                                HStack(spacing: 4) {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.purple)
                                    Text("Secret Key")
                                }
                                .font(.caption)
                            }
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            Button("View Details") {
                                viewModel.showKeyDetails(for: selectedNode)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Deselect") {
                                viewModel.selectNode(nil)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                )
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func legendView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Web of Trust Legend")
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Trust Levels")
                    .font(.headline)

                ForEach([TrustLevel.unknown, .never, .marginal, .full, .ultimate], id: \.self) { level in
                    HStack {
                        Circle()
                            .fill(trustColor(for: level))
                            .frame(width: 16, height: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.displayName)
                                .font(.subheadline)
                            Text(level.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Graph Elements")
                    .font(.headline)

                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.blue)
                    Text("Key (node)")
                }

                HStack {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                    Text("Signature (edge)")
                }

                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.purple)
                    Text("Secret key")
                }
            }

            Spacer()

            Button("Close") {
                showingLegend = false
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 400, height: 500)
    }

    private func trustColor(for level: TrustLevel) -> Color {
        switch level {
        case .unknown:
            return Color.gray
        case .never:
            return Color.red
        case .marginal:
            return Color.orange
        case .full:
            return Color.green
        case .ultimate:
            return Color.purple
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let showKeyDetails = Notification.Name("showKeyDetails")
    static let keysReloaded = Notification.Name("keysReloaded")
}
