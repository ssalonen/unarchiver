import Foundation

final class DocumentNode: Identifiable {
    let id = UUID()
    let label: String
    var value: String?
    var line: Int
    var children: [DocumentNode]
    var isLeaf: Bool { children.isEmpty }

    init(_ label: String, value: String? = nil, line: Int = 0, children: [DocumentNode] = []) {
        self.label = label
        self.value = value
        self.line = line
        self.children = children
    }
}

struct NavigatorScrollTarget: Equatable {
    let line: Int
    let token: UUID

    init(line: Int) {
        self.line = line
        self.token = UUID()
    }
}
