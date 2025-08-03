//
//  PhotoUtils.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-30.
//

import Foundation
import Photos
import UIKit
import Vision
import CoreML

let model = try! VNCoreMLModel(for: Resnet50Headless().model)

// 取得分類全部照片
func fetchAssets(for category: PhotoCategory) async -> [PHAsset] {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    var arr: [PHAsset] = []

    switch category {
    case .selfie:
        let collection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
        collection.enumerateObjects { col, _, _ in
            let assets = PHAsset.fetchAssets(in: col, options: options)
            assets.enumerateObjects { asset, _, _ in arr.append(asset) }
        }
    case .portrait:
        options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", PHAssetMediaSubtype.photoDepthEffect.rawValue)
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
    case .screenshot:
        options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
 
    case .photo:
        let selfieCollection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
        var selfieIds: Set<String> = []
        selfieCollection.enumerateObjects { col, _, _ in
            let selfieAssets = PHAsset.fetchAssets(in: col, options: nil)
            selfieAssets.enumerateObjects { asset, _, _ in
                selfieIds.insert(asset.localIdentifier)
            }
        }
        let allImages = PHAsset.fetchAssets(with: .image, options: options)
        allImages.enumerateObjects { asset, _, _ in
            let isSelfie = selfieIds.contains(asset.localIdentifier)
            let isPortrait = asset.mediaSubtypes.contains(.photoDepthEffect)
            let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            if !isSelfie && !isPortrait && !isScreenshot {
                arr.append(asset)
            }
        }
    }
    return arr
}

// 取得資產圖
func loadImages(from assets: [PHAsset]) async -> [UIImage] {
    await withCheckedContinuation { continuation in
        var images: [UIImage] = []
        let manager = PHImageManager.default()
        let reqOpts = PHImageRequestOptions()
        reqOpts.isSynchronous = false
        reqOpts.deliveryMode = .highQualityFormat
        let group = DispatchGroup()
        for asset in assets {
            group.enter()
            manager.requestImage(for: asset, targetSize: CGSize(width: 224, height: 224), contentMode: .aspectFill, options: reqOpts) { img, _ in
                if let img = img { images.append(img) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            continuation.resume(returning: images)
        }
    }
}

// 產生 embedding（單張圖）
func extractEmbedding(from image: UIImage) async -> [Float]? {
    await withCheckedContinuation { continuation in
        guard let ciImage = CIImage(image: image) else {
            continuation.resume(returning: nil)
            return
        }
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        let request = VNCoreMLRequest(model: model) { req, _ in
            if let obs = req.results?.first as? VNCoreMLFeatureValueObservation,
               let arr = obs.featureValue.multiArrayValue {
                let floats = (0..<arr.count).map { Float(truncating: arr[$0]) }
                continuation.resume(returning: floats)
            } else {
                continuation.resume(returning: nil)
            }
        }
        do {
            try handler.perform([request])
        } catch {
            print("🔴 推論錯誤: \(error.localizedDescription)")
            continuation.resume(returning: nil)
        }
    }
}

// 批次產生所有 embedding
func batchExtractEmbeddings(images: [UIImage]) async -> [[Float]] {
    await withTaskGroup(of: [Float]?.self) { group in
        for img in images {
            group.addTask { await extractEmbedding(from: img) }
        }
        var results: [[Float]] = []
        for await vector in group {
            results.append(vector ?? [])
        }
        return results
    }
}

// 相似組找 groupSimilarImages
func groupSimilarImages(pairs: [(Int, Int)]) -> [[Int]] {
    var groups: [[Int]] = []
    var used = Set<Int>()
    for pair in pairs {
        let (a, b) = pair
        if used.contains(a) && used.contains(b) { continue }
        var merged = false
        for i in 0..<groups.count {
            if groups[i].contains(a) {
                groups[i].append(b)
                used.insert(b)
                merged = true
                break
            } else if groups[i].contains(b) {
                groups[i].append(a)
                used.insert(a)
                merged = true
                break
            }
        }
        if !merged {
            groups.append([a, b])
            used.insert(a)
            used.insert(b)
        }
    }
    for i in 0..<groups.count {
        groups[i] = Array(Set(groups[i])).sorted()
    }
    return groups.filter { $0.count > 1 }
}


