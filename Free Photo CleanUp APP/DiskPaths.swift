//
//  DiskPaths.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-04.
//

import Foundation

enum DiskPaths {
    static func appSupportURL() -> URL {
        let url = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = url
        try? u.setResourceValues(values)
        return u
    }

    static func summaryURL() -> URL {
        appSupportURL().appendingPathComponent("scan_summary_v2.json")
    }

    static func detailURL(for category: PhotoCategory) -> URL {
        appSupportURL().appendingPathComponent("scan_detail_\(category.rawValue)_v2.json")
    }
}
