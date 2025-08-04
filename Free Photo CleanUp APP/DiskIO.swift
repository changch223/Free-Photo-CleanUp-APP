//
//  DiskIO.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-04.
//

// DiskIO.swift
import Foundation

func saveSummary(_ summary: PersistedScanSummaryV2) {
    do {
        let data = try JSONEncoder().encode(summary)
        try data.write(to: DiskPaths.summaryURL(), options: .atomic)
    } catch {
        print("saveSummary error:", error)
    }
}

func loadSummary() -> PersistedScanSummaryV2? {
    let url = DiskPaths.summaryURL()
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PersistedScanSummaryV2.self, from: data)
    } catch {
        print("loadSummary error:", error)
        return nil
    }
}

func saveDetail(_ detail: ScanDetailV2, for category: PhotoCategory) {
    do {
        let data = try JSONEncoder().encode(detail)
        try data.write(to: DiskPaths.detailURL(for: category), options: .atomic)
    } catch {
        print("saveDetail error:", error)
    }
}

func loadDetail(for category: PhotoCategory) -> ScanDetailV2? {
    let url = DiskPaths.detailURL(for: category)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ScanDetailV2.self, from: data)
    } catch {
        print("loadDetail error:", error)
        return nil
    }
}
