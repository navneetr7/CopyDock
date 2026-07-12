import Foundation
import AppKit

protocol BlobStoring {
    func save(data: Data, preferredExtension: String) throws -> String
    func load(relativePath: String) throws -> Data
    func delete(relativePath: String) throws
    func cleanupOrphaned(currentRelativePaths: Set<String>)
}

final class BlobStore: BlobStoring {

    private let fileManager = FileManager.default
    private let baseDirectory: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("CopyDock/Blobs", isDirectory: true)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func save(data: Data, preferredExtension: String) throws -> String {
        let filename = "\(UUID().uuidString).\(preferredExtension)"
        let url = baseDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    func load(relativePath: String) throws -> Data {
        try Data(contentsOf: baseDirectory.appendingPathComponent(relativePath))
    }

    func delete(relativePath: String) throws {
        try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(relativePath))
    }

    func cleanupOrphaned(currentRelativePaths: Set<String>) {
        guard let items = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else { return }
        for fileURL in items where !currentRelativePaths.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
