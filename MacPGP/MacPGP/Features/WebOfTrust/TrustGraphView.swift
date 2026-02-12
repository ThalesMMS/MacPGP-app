import SwiftUI

struct TrustGraphView: View {
    let nodes: [TrustNode]
    let edges: [TrustEdge]
    let selectedNode: TrustNode?
    let onNodeSelected: (TrustNode?) -> Void

    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var hoveredNode: TrustNode?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(nsColor: .controlBackgroundColor)

                // Canvas for rendering graph
                Canvas { context, size in
                    // Calculate node positions if not yet set
                    if nodePositions.isEmpty {
                        // Will be set in onAppear
                        return
                    }

                    // Apply zoom and pan transformation
                    var transformedContext = context
                    transformedContext.translateBy(x: offset.width, y: offset.height)
                    transformedContext.scaleBy(x: scale, y: scale)

                    // Draw edges first (so they appear behind nodes)
                    drawEdges(context: transformedContext, size: size)

                    // Draw nodes
                    drawNodes(context: transformedContext, size: size)
                }
                .gesture(
                    SimultaneousGesture(
                        magnificationGesture,
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Check if this is a pan (movement > threshold) or tap
                                if isPanning(value) {
                                    handlePan(value)
                                }
                            }
                            .onEnded { value in
                                // Only handle as tap if minimal movement
                                if !isPanning(value) {
                                    handleTap(at: value.location, in: geometry.size)
                                } else {
                                    // End panning
                                    lastOffset = offset
                                }
                            }
                    )
                )

                // Overlay for node labels and hover effects
                ForEach(nodes, id: \.id) { node in
                    if let position = nodePositions[node.id] {
                        nodeLabel(for: node, at: position, in: geometry.size)
                    }
                }

                // Zoom controls overlay
                zoomControls
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .onAppear {
            calculateNodePositions()
        }
        .onChange(of: nodes.count) { _, _ in
            calculateNodePositions()
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { value in
                lastScale = scale
            }
    }

    private func isPanning(_ value: DragGesture.Value) -> Bool {
        let distance = sqrt(
            pow(value.translation.width, 2) + pow(value.translation.height, 2)
        )
        return distance > 5
    }

    private func handlePan(_ value: DragGesture.Value) {
        offset = CGSize(
            width: lastOffset.width + value.translation.width,
            height: lastOffset.height + value.translation.height
        )
    }

    @ViewBuilder
    private var zoomControls: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = min(scale * 1.2, 5.0)
                    lastScale = scale
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .help("Zoom In")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = max(scale / 1.2, 0.2)
                    lastScale = scale
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .help("Zoom Out")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .help("Reset View")
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .opacity(0.95)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Drawing Methods

    private func drawEdges(context: GraphicsContext, size: CGSize) {
        for edge in edges {
            guard let fromNorm = nodePositions[edge.from],
                  let toNorm = nodePositions[edge.to] else {
                continue
            }

            // Convert normalized positions to actual pixel coordinates
            let fromPos = CGPoint(x: fromNorm.x * size.width, y: fromNorm.y * size.height)
            let toPos = CGPoint(x: toNorm.x * size.width, y: toNorm.y * size.height)

            // Draw edge as a line with an arrow
            var path = Path()
            path.move(to: fromPos)
            path.addLine(to: toPos)

            context.stroke(
                path,
                with: .color(edgeColor(for: edge)),
                lineWidth: 1.5
            )

            // Draw arrow head
            let arrowSize: CGFloat = 8
            let angle = atan2(toPos.y - fromPos.y, toPos.x - fromPos.x)
            let arrowTip = CGPoint(
                x: toPos.x - nodeRadius * cos(angle),
                y: toPos.y - nodeRadius * sin(angle)
            )

            var arrowPath = Path()
            arrowPath.move(to: arrowTip)
            arrowPath.addLine(to: CGPoint(
                x: arrowTip.x - arrowSize * cos(angle - .pi / 6),
                y: arrowTip.y - arrowSize * sin(angle - .pi / 6)
            ))
            arrowPath.move(to: arrowTip)
            arrowPath.addLine(to: CGPoint(
                x: arrowTip.x - arrowSize * cos(angle + .pi / 6),
                y: arrowTip.y - arrowSize * sin(angle + .pi / 6)
            ))

            context.stroke(
                arrowPath,
                with: .color(edgeColor(for: edge)),
                lineWidth: 1.5
            )
        }
    }

    private func drawNodes(context: GraphicsContext, size: CGSize) {
        for node in nodes {
            guard let normPos = nodePositions[node.id] else { continue }

            // Convert normalized position to actual pixel coordinates
            let position = CGPoint(x: normPos.x * size.width, y: normPos.y * size.height)

            let isSelected = selectedNode?.id == node.id
            let isHovered = hoveredNode?.id == node.id
            let radius = isSelected || isHovered ? nodeRadius * 1.2 : nodeRadius

            // Draw outer ring for secret keys
            if node.key.isSecretKey {
                let ringPath = Circle()
                    .path(in: CGRect(
                        x: position.x - radius - 3,
                        y: position.y - radius - 3,
                        width: (radius + 3) * 2,
                        height: (radius + 3) * 2
                    ))

                context.stroke(
                    ringPath,
                    with: .color(.purple.opacity(0.6)),
                    lineWidth: 2
                )
            }

            // Draw node circle
            let nodePath = Circle()
                .path(in: CGRect(
                    x: position.x - radius,
                    y: position.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))

            context.fill(nodePath, with: .color(nodeColor(for: node)))

            // Draw selection/hover ring
            if isSelected || isHovered {
                context.stroke(
                    nodePath,
                    with: .color(isSelected ? .blue : .gray),
                    lineWidth: isSelected ? 3 : 2
                )
            } else {
                context.stroke(
                    nodePath,
                    with: .color(.black.opacity(0.2)),
                    lineWidth: 1
                )
            }
        }
    }

    @ViewBuilder
    private func nodeLabel(for node: TrustNode, at position: CGPoint, in size: CGSize) -> some View {
        let isSelected = selectedNode?.id == node.id
        let showLabel = isSelected || hoveredNode?.id == node.id || nodes.count <= 10

        if showLabel {
            // Transform position with zoom and pan
            let transformedPosition = transformPoint(position, in: size)

            VStack(spacing: 2) {
                Text(node.key.displayName)
                    .font(.caption)
                    .lineLimit(1)

                if isSelected {
                    Text(node.trustLevel.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .opacity(0.95)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
            .position(
                x: transformedPosition.x,
                y: transformedPosition.y - (nodeRadius * scale) - 20
            )
        }
    }

    // MARK: - Layout Calculation

    private func calculateNodePositions() {
        guard !nodes.isEmpty else { return }

        nodePositions.removeAll()

        if nodes.count == 1 {
            // Single node - place in center
            nodePositions[nodes[0].id] = CGPoint(x: 0.5, y: 0.5)
        } else {
            // Use force-directed layout simulation
            layoutNodesWithForceDirected()
        }
    }

    private func layoutNodesWithForceDirected() {
        // Initialize random positions
        var positions: [String: CGPoint] = [:]
        for (index, node) in nodes.enumerated() {
            let angle = 2 * .pi * Double(index) / Double(nodes.count)
            positions[node.id] = CGPoint(
                x: 0.5 + 0.3 * cos(angle),
                y: 0.5 + 0.3 * sin(angle)
            )
        }

        // Simple force-directed layout iterations
        let iterations = 50
        let repulsionStrength = 0.05
        let attractionStrength = 0.01
        let damping = 0.8

        var velocities: [String: CGPoint] = [:]
        for node in nodes {
            velocities[node.id] = .zero
        }

        for _ in 0..<iterations {
            var forces: [String: CGPoint] = [:]
            for node in nodes {
                forces[node.id] = .zero
            }

            // Repulsion between all nodes
            for i in 0..<nodes.count {
                for j in (i+1)..<nodes.count {
                    let node1 = nodes[i]
                    let node2 = nodes[j]

                    guard let pos1 = positions[node1.id],
                          let pos2 = positions[node2.id] else { continue }

                    let dx = pos2.x - pos1.x
                    let dy = pos2.y - pos1.y
                    let distanceSquared = max(dx * dx + dy * dy, 0.01)
                    let distance = sqrt(distanceSquared)

                    let force = repulsionStrength / distanceSquared
                    let fx = force * dx / distance
                    let fy = force * dy / distance

                    forces[node1.id]!.x -= fx
                    forces[node1.id]!.y -= fy
                    forces[node2.id]!.x += fx
                    forces[node2.id]!.y += fy
                }
            }

            // Attraction along edges
            for edge in edges {
                guard let pos1 = positions[edge.from],
                      let pos2 = positions[edge.to] else { continue }

                let dx = pos2.x - pos1.x
                let dy = pos2.y - pos1.y
                let distance = sqrt(dx * dx + dy * dy)

                if distance > 0 {
                    let force = attractionStrength * distance
                    let fx = force * dx / distance
                    let fy = force * dy / distance

                    forces[edge.from]!.x += fx
                    forces[edge.from]!.y += fy
                    forces[edge.to]!.x -= fx
                    forces[edge.to]!.y -= fy
                }
            }

            // Apply forces and update positions
            for node in nodes {
                guard let force = forces[node.id],
                      let velocity = velocities[node.id],
                      var position = positions[node.id] else { continue }

                var newVelocity = CGPoint(
                    x: velocity.x * damping + force.x,
                    y: velocity.y * damping + force.y
                )

                // Limit velocity
                let speed = sqrt(newVelocity.x * newVelocity.x + newVelocity.y * newVelocity.y)
                if speed > 0.05 {
                    newVelocity.x = newVelocity.x / speed * 0.05
                    newVelocity.y = newVelocity.y / speed * 0.05
                }

                velocities[node.id] = newVelocity

                position.x += newVelocity.x
                position.y += newVelocity.y

                // Keep within bounds with margin
                position.x = max(0.1, min(0.9, position.x))
                position.y = max(0.1, min(0.9, position.y))

                positions[node.id] = position
            }
        }

        nodePositions = positions
    }

    // MARK: - Interaction Handling

    private func handleTap(at location: CGPoint, in size: CGSize) {
        // Inverse transform tap location to account for zoom and pan
        let inverseTransformedPoint = inverseTransformPoint(location)

        // Convert inverse transformed tap location to normalized coordinates
        let normalizedPoint = CGPoint(
            x: inverseTransformedPoint.x / size.width,
            y: inverseTransformedPoint.y / size.height
        )

        // Find tapped node
        for node in nodes {
            guard let nodePos = nodePositions[node.id] else { continue }

            let dx = normalizedPoint.x - nodePos.x
            let dy = normalizedPoint.y - nodePos.y
            let distance = sqrt(dx * dx + dy * dy)

            // Distance threshold in normalized space
            let threshold = (nodeRadius * 1.5) / size.width

            if distance <= threshold {
                onNodeSelected(node)
                return
            }
        }

        // No node was tapped, deselect
        onNodeSelected(nil)
    }

    // MARK: - Transformation Helpers

    private func transformPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        // Convert normalized position to actual position, then apply zoom and pan
        let actualPos = CGPoint(
            x: point.x * size.width,
            y: point.y * size.height
        )

        return CGPoint(
            x: actualPos.x * scale + offset.width,
            y: actualPos.y * scale + offset.height
        )
    }

    private func inverseTransformPoint(_ point: CGPoint) -> CGPoint {
        // Reverse the zoom and pan transformation
        return CGPoint(
            x: (point.x - offset.width) / scale,
            y: (point.y - offset.height) / scale
        )
    }

    // MARK: - Styling

    private let nodeRadius: CGFloat = 20

    private func nodeColor(for node: TrustNode) -> Color {
        trustColor(for: node.trustLevel)
    }

    private func edgeColor(for edge: TrustEdge) -> Color {
        Color.secondary.opacity(0.4)
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

// MARK: - Preview

#Preview("Trust Graph - Empty") {
    TrustGraphView(
        nodes: [],
        edges: [],
        selectedNode: nil,
        onNodeSelected: { _ in }
    )
    .frame(width: 800, height: 600)
}

#Preview("Trust Graph - Sample") {
    let sampleNodes = [
        TrustNode(
            id: "node1",
            key: .preview,
            trustLevel: .ultimate
        ),
        TrustNode(
            id: "node2",
            key: .preview,
            trustLevel: .full
        ),
        TrustNode(
            id: "node3",
            key: .preview,
            trustLevel: .marginal
        )
    ]

    let sampleEdges = [
        TrustEdge(from: "node1", to: "node2", trustLevel: .ultimate),
        TrustEdge(from: "node2", to: "node3", trustLevel: .full)
    ]

    TrustGraphView(
        nodes: sampleNodes,
        edges: sampleEdges,
        selectedNode: nil,
        onNodeSelected: { _ in }
    )
    .frame(width: 800, height: 600)
}
