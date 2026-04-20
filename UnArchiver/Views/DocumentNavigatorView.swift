import SwiftUI

struct DocumentNavigatorView: View {
    let nodes: [DocumentNode]
    let onSelectLine: (Int) -> Void

    @State private var expandedIDs: Set<UUID>

    init(nodes: [DocumentNode], onSelectLine: @escaping (Int) -> Void) {
        self.nodes = nodes
        self.onSelectLine = onSelectLine
        // Auto-expand root and first child level
        var ids = Set<UUID>()
        for node in nodes {
            ids.insert(node.id)
            for child in node.children { ids.insert(child.id) }
        }
        self._expandedIDs = State(initialValue: ids)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(nodes) { node in
                    NodeRowView(
                        node: node,
                        depth: 0,
                        expandedIDs: $expandedIDs,
                        onSelectLine: onSelectLine
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }
}

private struct NodeRowView: View {
    let node: DocumentNode
    let depth: Int
    @Binding var expandedIDs: Set<UUID>
    let onSelectLine: (Int) -> Void

    private var isExpanded: Bool { expandedIDs.contains(node.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowButton
            if !node.isLeaf && isExpanded {
                ForEach(node.children) { child in
                    NodeRowView(
                        node: child,
                        depth: depth + 1,
                        expandedIDs: $expandedIDs,
                        onSelectLine: onSelectLine
                    )
                }
            }
        }
    }

    private var rowButton: some View {
        Button {
            if node.isLeaf {
                if node.line > 0 { onSelectLine(node.line) }
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded { expandedIDs.remove(node.id) }
                    else { expandedIDs.insert(node.id) }
                }
                if node.line > 0 { onSelectLine(node.line) }
            }
        } label: {
            HStack(spacing: 3) {
                indentSpacer
                disclosureIcon
                labelText
                valueText
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var indentSpacer: some View {
        if depth > 0 {
            HStack(spacing: 0) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 1)
                        .padding(.horizontal, 5)
                }
            }
        }
    }

    private var disclosureIcon: some View {
        Group {
            if !node.isLeaf {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(width: 10)
    }

    private var labelText: some View {
        Text(node.label)
            .font(.system(size: 11, weight: node.isLeaf ? .regular : .semibold, design: .monospaced))
            .foregroundStyle(node.isLeaf ? Color.secondary : Color.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var valueText: some View {
        if let value = node.value {
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
