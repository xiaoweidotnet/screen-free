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

enum RecordingProjectSidecar {
    static func url(for recordingURL: URL) -> URL {
        recordingURL.deletingPathExtension()
            .appendingPathExtension("screenfree")
    }

    static func backupURL(for recordingURL: URL) -> URL {
        url(for: recordingURL).appendingPathExtension("previous")
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

    /// Permanently removes the given recordings from disk. Only files that
    /// live directly inside the catalog directory are deleted; anything else
    /// is skipped. Returns the number of files actually removed.
    @discardableResult
    func delete(_ items: [RecordingHistoryItem]) -> Int {
        let directoryPath = directory.standardizedFileURL.path
        var deleted = 0
        for item in items {
            let url = item.url.standardizedFileURL
            guard url.deletingLastPathComponent().path == directoryPath else {
                continue
            }
            if (try? fileManager.removeItem(at: url)) != nil {
                let sidecarURL = RecordingProjectSidecar.url(for: url)
                if fileManager.fileExists(atPath: sidecarURL.path) {
                    try? fileManager.removeItem(at: sidecarURL)
                }
                let backupURL = RecordingProjectSidecar.backupURL(for: url)
                if fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.removeItem(at: backupURL)
                }
                deleted += 1
            }
        }
        return deleted
    }
}
