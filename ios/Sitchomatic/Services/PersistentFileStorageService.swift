import Foundation

@MainActor
final class PersistentFileStorageService {
    static let shared = PersistentFileStorageService()

    private let baseDirectory: URL
    private let fileManager: FileManager = .default
    private let logger = DebugLogger.shared

    private init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        baseDirectory = documentsDirectory.appendingPathComponent("SitchomaticV16", isDirectory: true)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func save(data: Data, filename: String) {
        let destinationURL = resolvedURL(for: filename)
        ensureParentDirectory(for: destinationURL)

        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            logger.log("File save failed: \(filename) — \(error.localizedDescription)", category: .persistence, level: .error)
        }
    }

    func save(text: String, filename: String) {
        save(data: Data(text.utf8), filename: filename)
    }

    func createDirectory(at relativePath: String) -> URL? {
        let directoryURL = resolvedURL(for: relativePath)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return directoryURL
        } catch {
            logger.log("Directory creation failed: \(relativePath) — \(error.localizedDescription)", category: .persistence, level: .error)
            return nil
        }
    }

    func load(filename: String) -> Data? {
        try? Data(contentsOf: resolvedURL(for: filename))
    }

    func delete(filename: String) {
        let targetURL = resolvedURL(for: filename)
        guard fileManager.fileExists(atPath: targetURL.path) else { return }

        do {
            try fileManager.removeItem(at: targetURL)
        } catch {
            logger.log("Delete failed: \(filename) — \(error.localizedDescription)", category: .persistence, level: .warning)
        }
    }

    func exists(filename: String) -> Bool {
        fileManager.fileExists(atPath: resolvedURL(for: filename).path)
    }

    func listFiles(in subdirectory: String = "") -> [String] {
        let directoryURL = subdirectory.isEmpty ? baseDirectory : resolvedURL(for: subdirectory)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) else { return [] }
        return contents.sorted()
    }

    func zipDirectory(at relativePath: String, archiveFilename: String) -> String? {
        let sourceDirectoryURL = resolvedURL(for: relativePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            logger.log("Zip source directory missing: \(relativePath)", category: .persistence, level: .warning)
            return nil
        }

        let destinationArchiveURL = resolvedURL(for: archiveFilename)
        ensureParentDirectory(for: destinationArchiveURL)

        var coordinationError: NSError?
        var storedArchivePath: String?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: sourceDirectoryURL, options: [.forUploading], error: &coordinationError) { temporaryArchiveURL in
            do {
                if fileManager.fileExists(atPath: destinationArchiveURL.path) {
                    try fileManager.removeItem(at: destinationArchiveURL)
                }

                do {
                    try fileManager.moveItem(at: temporaryArchiveURL, to: destinationArchiveURL)
                } catch {
                    try fileManager.copyItem(at: temporaryArchiveURL, to: destinationArchiveURL)
                }

                storedArchivePath = archiveFilename
            } catch {
                logger.log("Zip creation failed: \(archiveFilename) — \(error.localizedDescription)", category: .persistence, level: .error)
            }
        }

        if let coordinationError {
            logger.log("Zip coordination failed: \(archiveFilename) — \(coordinationError.localizedDescription)", category: .persistence, level: .error)
        }

        return storedArchivePath
    }

    func purgeAll() {
        try? fileManager.removeItem(at: baseDirectory)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        logger.log("All stored files purged", category: .persistence, level: .warning)
    }

    var storageSizeMB: Double {
        guard let enumerator = fileManager.enumerator(at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }

        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalBytes += Int64(size)
            }
        }

        return Double(totalBytes) / 1_048_576
    }

    private func resolvedURL(for relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    private func ensureParentDirectory(for fileURL: URL) {
        let directoryURL = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
