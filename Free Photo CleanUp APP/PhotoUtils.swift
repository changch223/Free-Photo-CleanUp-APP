//
//  PhotoUtils.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-30.
//

import Photos
import UIKit
import Vision
import CoreML

let model = try! VNCoreMLModel(for: Resnet50Headless().model)

func fetchFirst100Images(completion: @escaping ([UIImage]) -> Void) {
    var images: [UIImage] = []
    let fetchOptions = PHFetchOptions()
    fetchOptions.fetchLimit = 100
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)

    let imageManager = PHImageManager.default()
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.isSynchronous = false // ✅ 改為 false

    let group = DispatchGroup()

    results.enumerateObjects { asset, _, _ in
        group.enter()
        let targetSize = CGSize(width: 224, height: 224)
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, _ in
            if let img = image {
                images.append(img)
            }
            group.leave()
        }
    }

    group.notify(queue: .main) {
        completion(images)
    }
}

func extractEmbedding(from image: UIImage, completion: @escaping ([Float]?) -> Void) {
    guard let ciImage = CIImage(image: image) else {
        completion(nil)
        return
    }

    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    let request = VNCoreMLRequest(model: model) { req, _ in
        if let obs = req.results?.first as? VNCoreMLFeatureValueObservation,
           let arr = obs.featureValue.multiArrayValue {
            let floats = (0..<arr.count).map { Float(truncating: arr[$0]) }
            completion(floats)
        } else {
            completion(nil)
        }
    }

    do {
        try handler.perform([request])
    } catch {
        print("🔴 推論錯誤: \(error.localizedDescription)")
        completion(nil)
    }
}
