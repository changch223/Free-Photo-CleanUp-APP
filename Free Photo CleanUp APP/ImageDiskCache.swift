//
//  ImageDiskCache.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-03.
//

import UIKit

func saveImagesToDisk(_ images: [UIImage], for category: PhotoCategory) {
    let dir = imagesCacheDirectory(for: category)
    print("儲存路徑：", dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    for (i, img) in images.enumerated() {
        if let data = img.jpegData(compressionQuality: 0.85) {
            let url = dir.appendingPathComponent("\(i).jpg")
            try? data.write(to: url)
        }
    }
}

func loadImagesFromDisk(for category: PhotoCategory) -> [UIImage] {
    let dir = imagesCacheDirectory(for: category)
    print("讀取路徑：", dir)
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    print("讀取到檔案：", files)
    return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { UIImage(contentsOfFile: $0.path) }
}

private func imagesCacheDirectory(for category: PhotoCategory) -> URL {
    let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return doc.appendingPathComponent("imgcache_\(category.rawValue)", isDirectory: true)
}
