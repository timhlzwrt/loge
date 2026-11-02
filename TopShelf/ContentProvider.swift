import TVServices

/// Feasibility test: one item per check, so the shelf shows where sharing with Loge breaks.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let group = AppGroup.identifier
        let container = group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        let defaults = group.flatMap { UserDefaults(suiteName: $0)?.string(forKey: AppGroup.testKey) }
        let file = container.flatMap { try? String(contentsOf: $0.appending(path: AppGroup.testFile), encoding: .utf8) }

        let lines = [
            "Group: \(group ?? "none in profile")",
            "Container: \(container == nil ? "no" : "yes")",
            "Defaults: \(defaults ?? "missing")",
            "File: \(file ?? "missing")",
        ]
        let items = lines.enumerated().map { index, line in
            let item = TVTopShelfSectionedItem(identifier: "check\(index)")
            item.title = line
            item.imageShape = .hdtv
            item.setImageURL(URL(string: "https://images.metahub.space/background/medium/tt0903747/img"), for: .screenScale1x)
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Top Shelf test"
        completionHandler(TVTopShelfSectionedContent(sections: [section]))
    }
}
