//
//  Models.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-04.
//

// Models.swift
import Foundation
import Photos

struct PersistedScanSummaryV2: Codable {
    struct CategorySummary: Codable {
        var date: Date
        var duplicateCount: Int
        var totalAssetsAtScan: Int
        var librarySignature: LibrarySignature
    }
    var version: Int = 2
    var categories: [PhotoCategory.RawValue: CategorySummary]
}

struct ScanDetailV2: Codable {
    var version: Int = 2
    var category: PhotoCategory.RawValue
    var date: Date
    var assetIds: [String]
    var lastGroups: [[Int]]
    var librarySignature: LibrarySignature
}

// 用來快速判斷是否過期
struct LibrarySignature: Codable, Equatable {
    var assetCount: Int
    var firstID: String?
    var lastID: String?
    // 可再加：hash(前N個IDs)、latestCreationDate 之類
}

func makeSignature(for assets: [PHAsset]) -> LibrarySignature {
    let count = assets.count
    let firstID = assets.first?.localIdentifier
    let lastID  = assets.last?.localIdentifier
    return LibrarySignature(assetCount: count, firstID: firstID, lastID: lastID)
}
