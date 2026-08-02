import Foundation

struct RecordingHistoryItem: Identifiable, Equatable, Sendable {
    let url: URL
    let modifiedAt: Date
    let fileSize: Int64

    var id: String {
        url.standardizedFileURL.path
    }

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct RecordingHistoryCatalog {
    let directory: URL
    private let fileManager: FileManager

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directory = directory
            ?? fileManager.urls(
                for: .moviesDirectory,
                in: .userDomainMask
            ).first?.appendingPathComponent(
                "ScreenFree",
                isDirectory: true
            )
            ?? fileManager.temporaryDirectory.appendingPathComponent(
                "ScreenFree",
                isDirectory: true
            )
    }

    func recordings(limit: Int = 100) -> [RecordingHistoryItem] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url -> RecordingHistoryItem? in
            guard ["mp4", "mov"].contains(
                url.pathExtension.lowercased()
            ),
            let values = try? url.resourceValues(forKeys: keys),
            values.isRegularFile == true else {
                return nil
            }
            return RecordingHistoryItem(
                url: url.standardizedFileURL,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                fileSize: Int64(values.fileSize ?? 0)
            )
        }
        .sorted {
            if $0.modifiedAt == $1.modifiedAt {
                return $0.url.lastPathComponent
                    .localizedStandardCompare($1.url.lastPathComponent)
                    == .orderedAscending
            }
            return $0.modifiedAt > $1.modifiedAt
        }
        .prefix(max(0, limit))
        .map(\.self)
    }
}
