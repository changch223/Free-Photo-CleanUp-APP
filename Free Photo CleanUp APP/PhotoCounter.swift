//
//  PhotoCounter.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-04.
//


import Foundation
import Photos

struct PhotoCounter {

    /// 只回傳張數，不載入圖片，適合在背景執行緒呼叫
    static func fetchAssetCount(for category: PhotoCategory) -> Int {
        // 沒權限時回 0，避免觸發昂貴查詢
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return 0
        }

        switch category {
        case .selfie:
            // iOS 內建「自拍」相簿
            let options = PHFetchOptions()
            var count = 0
            let col = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                              subtype: .smartAlbumSelfPortraits,
                                                              options: nil)
            col.enumerateObjects { album, _, _ in
                count += PHAsset.fetchAssets(in: album, options: options).count
            }
            return count

        case .portrait:
            // 人像（景深）照片
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "mediaSubtypes & %d != 0",
                                      PHAssetMediaSubtype.photoDepthEffect.rawValue)
            return PHAsset.fetchAssets(with: .image, options: o).count

        case .screenshot:
            // 螢幕截圖
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "mediaSubtypes & %d != 0",
                                      PHAssetMediaSubtype.photoScreenshot.rawValue)
            return PHAsset.fetchAssets(with: .image, options: o).count

        case .photo:
            // 一般照片：排除 selfie / portrait / screenshot
            // 作法：先篩掉 portrait / screenshot 的母集合，再扣掉該集合中的 selfie 數量

            // 1) 先取「非 portrait / 非 screenshot」的所有照片
            let baseOpt = PHFetchOptions()
            baseOpt.predicate = NSPredicate(format:
                "NOT (mediaSubtypes & %d != 0) AND NOT (mediaSubtypes & %d != 0)",
                PHAssetMediaSubtype.photoDepthEffect.rawValue,
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            let baseCount = PHAsset.fetchAssets(with: .image, options: baseOpt).count

            // 2) selfie 相簿裡，符合同樣 baseOpt 條件的張數
            let selfieCol = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                    subtype: .smartAlbumSelfPortraits,
                                                                    options: nil)
            var selfieFilteredCount = 0
            selfieCol.enumerateObjects { album, _, _ in
                selfieFilteredCount += PHAsset.fetchAssets(in: album, options: baseOpt).count
            }

            // 3) 相減 = 非 selfie / 非 portrait / 非 screenshot
            return max(0, baseCount - selfieFilteredCount)
        }
    }
}
