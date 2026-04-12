import SwiftUI

struct FileRowView: View {
    let entry: ArchiveEntry
    let onTap: () -> Void
    let onShare: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: entry.icon)
                    .frame(width: 28, alignment: .center)
                    .font(.title3)
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(entry.sizeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let date = entry.modificationDate {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if entry.path.contains("/") {
                            Text(pathPrefix)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)

                if entry.isTextFile {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { onShare() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button { onTap() } label: {
                Label(entry.isTextFile ? "View" : "Preview", systemImage: "eye")
            }
            Button { onShare() } label: {
                Label("Share / Export", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var pathPrefix: String {
        let components = entry.path.split(separator: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    private var iconColor: Color {
        switch (entry.icon) {
        case "folder":                                      return .yellow
        case "photo":                                       return .green
        case "film":                                        return .purple
        case "music.note":                                  return .pink
        case "doc.richtext":                                return .red
        case "chevron.left.forwardslash.chevron.right":     return .blue
        case "curlybraces":                                 return .orange
        case "terminal":                                    return .green
        case "globe":                                       return .blue
        default:                                            return .secondary
        }
    }
}
