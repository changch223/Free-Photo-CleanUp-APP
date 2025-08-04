//
//  ViewModel.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-03.
//

import Foundation
import Photos

class PhotoLibraryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var categoryCounts: [PhotoCategory: Int] = [:]
    @Published var countsLoading = true

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        refreshCategoryCounts()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.refreshCategoryCounts()
        }
    }

    func refreshCategoryCounts() {
        countsLoading = true
        Task.detached(priority: .background) {
            var tmp: [PhotoCategory: Int] = [:]
            for cat in PhotoCategory.allCases {
                let c = self.fetchAssetCount(for: cat)
                tmp[cat] = c
            }
            await MainActor.run {
                self.categoryCounts = tmp
                self.countsLoading = false
            }
        }
    }

    func fetchAssetCount(for category: PhotoCategory) -> Int {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch category {
        case .selfie:
            let col = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
            var count = 0
            col.enumerateObjects { album, _, _ in
                count += PHAsset.fetchAssets(in: album, options: options).count
            }
            return count
        case .portrait:
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "mediaSubtypes & %d != 0",
                                      PHAssetMediaSubtype.photoDepthEffect.rawValue)
            return PHAsset.fetchAssets(with: .image, options: o).count
        case .screenshot:
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "mediaSubtypes & %d != 0",
                                      PHAssetMediaSubtype.photoScreenshot.rawValue)
            return PHAsset.fetchAssets(with: .image, options: o).count
        case .photo:
            let baseOpt = PHFetchOptions()
            baseOpt.predicate = NSPredicate(format:
                "NOT (mediaSubtypes & %d != 0) AND NOT (mediaSubtypes & %d != 0)",
                PHAssetMediaSubtype.photoDepthEffect.rawValue,
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            let baseCount = PHAsset.fetchAssets(with: .image, options: baseOpt).count

            let selfieCol = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
            var selfieFilteredCount = 0
            selfieCol.enumerateObjects { album, _, _ in
                selfieFilteredCount += PHAsset.fetchAssets(in: album, options: baseOpt).count
            }
            return max(0, baseCount - selfieFilteredCount)
        }
    }
}
