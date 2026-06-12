import Foundation
import SwiftData

@MainActor
protocol HistoryStoring {
    func fetchAll() async throws -> [ClipboardItem]
    func insert(_ item: ClipboardItem) async throws
    func delete(_ item: ClipboardItem) async throws
    func clearAll(includePinned: Bool) async throws
    func togglePin(_ item: ClipboardItem) async throws
    func prune(maxCount: Int, maxAgeDays: Int) async throws
}

@MainActor
final class HistoryStore: HistoryStoring {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try modelContext.fetch(descriptor)
    }

    func insert(_ item: ClipboardItem) async throws {
        modelContext.insert(item)
        try modelContext.save()
        try await prune(
            maxCount: UserSettings.shared.effectiveHistoryLimit,
            maxAgeDays: UserSettings.shared.retentionDays
        )
    }

    func delete(_ item: ClipboardItem) async throws {
        let blobPaths = item.contents.compactMap { c -> String? in
            c.type == "clipy.blob" ? c.stringValue : nil
        }
        let store = BlobStore()
        for path in blobPaths { try? store.delete(relativePath: path) }
        modelContext.delete(item)
        try modelContext.save()
    }

    func clearAll(includePinned: Bool) async throws {
        let all = try await fetchAll()
        let toDelete = includePinned ? all : all.filter { !$0.isPinned }
        let store = BlobStore()
        for item in toDelete {
            let blobPaths = item.contents.compactMap { c -> String? in
                c.type == "clipy.blob" ? c.stringValue : nil
            }
            for p in blobPaths { try? store.delete(relativePath: p) }
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    func togglePin(_ item: ClipboardItem) async throws {
        if item.isPinned {
            item.isPinned = false
        } else {
            let pinnedLimit = UserSettings.shared.effectivePinnedLimit
            if pinnedLimit > 0 {
                let pinnedCount = try await fetchAll().filter(\.isPinned).count
                guard pinnedCount < pinnedLimit else { return }
            }
            item.isPinned = true
        }
        try modelContext.save()
    }

    func prune(maxCount: Int, maxAgeDays: Int) async throws {
        let all = try await fetchAll()
        var unpinned = all.filter { !$0.isPinned }

        let store = BlobStore()

        if maxAgeDays > 0 {
            let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: .now) ?? .distantPast
            let toDeleteByAge = unpinned.filter { $0.timestamp < cutoff }
            for item in toDeleteByAge {
                item.contents.compactMap { $0.type == "clipy.blob" ? $0.stringValue : nil }
                    .forEach { try? store.delete(relativePath: $0) }
                modelContext.delete(item)
            }
            unpinned.removeAll { $0.timestamp < cutoff }
        }

        if maxCount > 0, unpinned.count > maxCount {
            let toDeleteByCount = unpinned.suffix(from: maxCount)
            for item in toDeleteByCount {
                item.contents.compactMap { $0.type == "clipy.blob" ? $0.stringValue : nil }
                    .forEach { try? store.delete(relativePath: $0) }
                modelContext.delete(item)
            }
        }

        try modelContext.save()
    }
}
