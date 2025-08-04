//
//  ViewModel.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-03.
//

import Foundation
import Photos

final class PhotoLibraryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var categoryCounts: [PhotoCategory: Int] = [:]
    @Published var countsLoading = true

    private var pendingRefresh = false

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        refreshCategoryCounts()
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard !pendingRefresh else { return }
        pendingRefresh = true
        // 300ms 內合併多次變更
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.refreshCategoryCounts()
            self.pendingRefresh = false
        }
    }

    func refreshCategoryCounts() {
        countsLoading = true
        Task.detached(priority: .background) {
            var tmp: [PhotoCategory: Int] = [:]
            for cat in PhotoCategory.allCases {
                tmp[cat] = PhotoCounter.fetchAssetCount(for: cat) // 參考你現有的只做 count 版本
            }
            await MainActor.run {
                self.categoryCounts = tmp
                self.countsLoading = false
            }
        }
    }
}
