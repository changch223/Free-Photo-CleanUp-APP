//
//  BlurryImagesEntryView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-16.
//


import SwiftUI
import Photos

struct BlurryImagesEntryView: View {
    let category: PhotoCategory
    let blurryResult: BlurryScanResult

    var body: some View {
        // 把每張模糊照片變成一個只有 1 張的群組 [[i], [j], ...]
        let singletonGroups = blurryResult.blurryIndices.map { [$0] }
        SimilarImagesView(
            similarPairs: [],                       // 不用相似對，改傳自訂群組
            assetIds: blurryResult.assetIds,
            customGroups: singletonGroups,          // <- 使用自訂群組
            defaultKeepMode: .none                  // <- 預設全部不勾選
        )
        .navigationTitle(
            String(format: NSLocalizedString("nav_title_view_blurry", comment: ""), category.localizedName)
        )
    }
}
