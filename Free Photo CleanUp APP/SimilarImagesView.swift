//
//  SimilarImagesView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-30.
//

import SwiftUI
import Photos
import UIKit

/// 進入「查看」時的啟動器：先讀磁碟 detail，再轉去 SimilarImagesView
struct SimilarImagesEntryView: View {
    let category: PhotoCategory
    let inlineResult: ScanResult?

    @State private var isLoading = true
    @State private var assetIds: [String] = []
    @State private var pairs: [(Int, Int)] = []
    @State private var warningStale = false  // 可選：若 signature 不同可提示資料可能過期

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView("loading_scan_result")
                    if warningStale {
                        Text("stale_data_warning")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            } else if !assetIds.isEmpty {
                // 沿用相似群組的檢視（預設模式：每組第一張勾選）
                SimilarImagesView(
                    similarPairs: pairs,
                    assetIds: assetIds
                )
                .overlay(alignment: .topTrailing) {
                    if warningStale {
                        Text("stale_data_warning")
                            .font(.caption2).bold()
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(8)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("not_found_detail_title")
                        .font(.headline)
                    Text("not_found_detail_msg")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
            }
        }
        .navigationTitle(String(format: NSLocalizedString("nav_title_view_category", comment: ""), category.localizedName))
        .task { await loadDetailOrFallback() }
    }

    /// 讀 detail 檔；若無則退回 inline 結果
    private func loadDetailOrFallback() async {
        // 先嘗試讀取磁碟
        if let detail = loadDetail(for: category) {
            // 可選：與目前資料簽章比對，設 warning
            // let nowSig = await currentSignature(for: category)
            // warningStale = (nowSig != detail.librarySignature)

            assetIds = detail.assetIds
            pairs = pairsFromGroups(detail.lastGroups)
            isLoading = false
            return
        }

        // 退回 inline（當次掃描還在記憶體中的資料）
        if let inline = inlineResult, !inline.assetIds.isEmpty {
            assetIds = inline.assetIds
            pairs = pairsFromGroups(inline.lastGroups)
        } else {
            assetIds = []
            pairs = []
        }
        isLoading = false
    }
}

/// 可同時支援：
/// 1) 相似照片群組（使用 similarPairs）
/// 2) 自訂群組（customGroups，例：模糊照片每張是一組）
/// 並可指定預設勾選模式（defaultKeepMode：.first / .none）
struct SimilarImagesView: View {
    let similarPairs: [(Int, Int)]
    let assetIds: [String]

    /// 若提供，將覆蓋相似群組；用於「模糊照片每張單獨一組」等情境
    let customGroups: [[Int]]?
    /// 預設勾選策略：.first（每組預設勾第一張）、.none（全部不勾）
    enum DefaultKeepMode { case first, none }
    let defaultKeepMode: DefaultKeepMode

    /// 與既有呼叫相容的便利 init（提供預設值）
    init(
        similarPairs: [(Int, Int)],
        assetIds: [String],
        customGroups: [[Int]]? = nil,
        defaultKeepMode: DefaultKeepMode = .first
    ) {
        self.similarPairs = similarPairs
        self.assetIds = assetIds
        self.customGroups = customGroups
        self.defaultKeepMode = defaultKeepMode
    }

    static var imageCache = NSCache<NSString, UIImage>()

    @State private var selectedKeep: [Int: Set<Int>] = [:]
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var reviewingGroupIndex: Int? = nil

    // 記錄所有已刪除的 global index
    @State private var deletedIndices: Set<Int> = []

    // 只顯示未被刪除的 group（群組來源：customGroups ?? groupSimilarImages）
    var grouped: [[Int]] {
        let baseGroups = customGroups ?? groupSimilarImages(pairs: similarPairs)
        return baseGroups
            .map { $0.filter { !deletedIndices.contains($0) } }
            .filter { !$0.isEmpty }
    }

    var allKeepIndices: Set<Int> {
        Set(selectedKeep.values.flatMap { $0 })
    }
    var allDeleteIndices: [Int] {
        grouped.enumerated().flatMap { (gIdx, group) in
            group.filter { !(selectedKeep[gIdx]?.contains($0) ?? false) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { (groupIdx, group) in
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(group, id: \.self) { idx in
                                        ThumbnailView(
                                            assetID: assetIds[safe: idx] ?? "",
                                            isSelected: selectedKeep[groupIdx]?.contains(idx) ?? false
                                        ) {
                                            if selectedKeep[groupIdx]?.contains(idx) == true {
                                                selectedKeep[groupIdx]?.remove(idx)
                                            } else {
                                                selectedKeep[groupIdx, default: []].insert(idx)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                            }
                            HStack {
                                Text(String(format: NSLocalizedString("select_keep", comment: ""),
                                            selectedKeep[groupIdx]?.count ?? 0, group.count))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Button {
                                    reviewingGroupIndex = groupIdx
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "rectangle.and.magnifyingglass")
                                        Text("btn_advanced_filter")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.top)
                .padding(.bottom, 8)
            }
        }
        // 把底部工具列 + Banner 合併成一個 inset
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(String(format: NSLocalizedString("batch_action_summary", comment: ""),
                                allKeepIndices.count, allDeleteIndices.count))
                        .font(.footnote)
                    Spacer()
                    Button(action: { showDeleteConfirm = true }) {
                        Text(isDeleting
                             ? NSLocalizedString("btn_deleting", comment: "")
                             : NSLocalizedString("btn_batch_delete", comment: ""))
                            .fontWeight(.bold)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(allDeleteIndices.isEmpty || isDeleting ? Color.gray : Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(allDeleteIndices.isEmpty || isDeleting)
                }
                .padding()
                .background(.ultraThinMaterial)

                BannerAdView(adUnitID: "ca-app-pub-9275380963550837/9201898058")
                    .frame(height: 50)
            }
        }
        .navigationTitle("nav_title_similar_group")
        .onAppear {
            // 依預設模式建立初始勾選
            var initial: [Int: Set<Int>] = [:]
            let baseGroups = customGroups ?? groupSimilarImages(pairs: similarPairs)
            for (i, group) in baseGroups.enumerated() {
                switch defaultKeepMode {
                case .first:
                    if let first = group.first { initial[i] = [first] }
                case .none:
                    initial[i] = [] // 全不勾選
                }
            }
            selectedKeep = initial
            Task.detached { await pickAllFavoritesAsDefaultKeep() }
        }
        .alert("confirm_delete_title", isPresented: $showDeleteConfirm) {
            Button("btn_cancel", role: .cancel) {}
            Button("btn_delete", role: .destructive) { performDelete() }
        } message: {
            Text(String(format: NSLocalizedString("confirm_delete_msg", comment: ""), allDeleteIndices.count))
        }
        .alert("delete_failed_title", isPresented: Binding(get: { deleteError != nil }, set: { _ in deleteError = nil })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .fullScreenCover(item: Binding(
            get: { reviewingGroupIndex.map { ReviewToken(id: $0) } },
            set: { token in reviewingGroupIndex = token?.id }
        )) { token in
            let gIdx = token.id
            let memberIndices = grouped[safe: gIdx] ?? []
            let memberIDs = memberIndices.compactMap { assetIds[safe: $0] }

            AdvancedReviewViewSwipe(
                assetIDs: memberIDs,
                initiallyKept: selectedKeep[gIdx] ?? [],
                mapToGlobalIndex: { local in memberIndices[safe: local] },
                onFinish: { keptGlobals in
                    selectedKeep[gIdx] = keptGlobals
                    reviewingGroupIndex = nil
                },
                onCancel: {
                    reviewingGroupIndex = nil
                }
            )
        }
    }

    // 只要是最愛都加到保留（全 group 內檢查）
    private func pickAllFavoritesAsDefaultKeep() async {
        let baseGroups = customGroups ?? groupSimilarImages(pairs: similarPairs)
        await withTaskGroup(of: (Int, Set<Int>).self) { group in
            for (gIdx, members) in baseGroups.enumerated() {
                group.addTask {
                    var favoriteIndices: Set<Int> = []
                    for idx in members {
                        guard let id = assetIds[safe: idx] else { continue }
                        let fr = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                        guard let asset = fr.firstObject else { continue }
                        if asset.isFavorite {
                            favoriteIndices.insert(idx)
                        }
                    }
                    return (gIdx, favoriteIndices)
                }
            }
            var newKeep = selectedKeep
            for await (gIdx, favs) in group {
                // 若該 group 有最愛，把全部最愛都設為保留；沒有最愛則維持原本預設
                if !favs.isEmpty { newKeep[gIdx] = favs }
            }
            await MainActor.run { self.selectedKeep = newKeep }
        }
    }

    // 用 deletedIndices 馬上讓被刪除照片消失
    private func performDelete() {
        let idsToDelete: [String] = allDeleteIndices.compactMap { assetIds[safe: $0] }
        let indicesToDelete = Set(allDeleteIndices)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: idsToDelete, options: nil)
        guard fetch.count > 0 else { return }
        isDeleting = true
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(fetch as NSFastEnumeration)
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                self.isDeleting = false
                if let error = error {
                    self.deleteError = error.localizedDescription
                    return
                }
                // 1) 刪除成功：記錄下已刪除 index，UI 自動消失
                self.deletedIndices.formUnion(indicesToDelete)
                // 2) selectedKeep 也要移除這些 index，避免資料殘留
                var newSelectedKeep = self.selectedKeep
                for gIdx in newSelectedKeep.keys {
                    newSelectedKeep[gIdx]?.subtract(indicesToDelete)
                }
                self.selectedKeep = newSelectedKeep
            }
        })
    }

    private struct ReviewToken: Identifiable { let id: Int }
}

// MARK: - 縮圖 cell
struct ThumbnailView: View {
    let assetID: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var thumb: UIImage?
    @State private var isFavorite: Bool = false

    var body: some View {
        ZStack {
            Group {
                if let img = thumb {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 80, height: 80)
            .clipped()
            .cornerRadius(12)
            .shadow(radius: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green : Color.gray.opacity(0.3), lineWidth: 3)
            )
            .onTapGesture(perform: onTap)
            .onAppear {
                loadThumbnail()
                fetchFavoriteStatus()
            }
        }
        // 愛心（左上角）
        .overlay(alignment: .topLeading) {
            if isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .shadow(radius: 1)
                    .padding(.leading, 6)
                    .padding(.top, 6)
            }
        }
        // 勾勾（右上角）
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .offset(x: -5, y: 5)
            }
        }
    }

    private func loadThumbnail() {
        guard !assetID.isEmpty else { return }
        let fr = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fr.firstObject else { return }
        let target = CGSize(width: 80 * UIScreen.main.scale, height: 80 * UIScreen.main.scale)
        Task {
            let key = "\(assetID)#thumb" as NSString
            if let cached = SimilarImagesView.imageCache.object(forKey: key) {
                self.thumb = cached
                return
            }
            let img = await requestImageAsyncOnce(asset, target: target, mode: .aspectFill)
            if let img {
                SimilarImagesView.imageCache.setObject(img, forKey: key)
                self.thumb = img
            }
        }
    }

    private func fetchFavoriteStatus() {
        guard !assetID.isEmpty else { return }
        let fr = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fr.firstObject else { return }
        self.isFavorite = asset.isFavorite
    }
}

// MARK: - 交友app式進階篩選＋反饋
struct AdvancedReviewViewSwipe: View {
    let assetIDs: [String]
    let initiallyKept: Set<Int>
    let mapToGlobalIndex: (Int) -> Int?
    let onFinish: (Set<Int>) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var localKeep: Set<Int> = []
    @State private var feedbackText: String? = nil
    @State private var feedbackColor: Color = .green
    @State private var feedbackOpacity: Double = 0
    @State private var isFavorite: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                if assetIDs.indices.contains(currentIndex) {
                    ZoomableImageView(
                        assetID: assetIDs[currentIndex],
                        placeholder: Color.black.opacity(0.9)
                    )
                    // 最愛大icon + 標籤 + 畫面上方顯示目前進度及狀態
                    .overlay(alignment: .top) {
                        HStack {
                            if isFavorite {
                                HStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 20))
                                        .shadow(radius: 3)
                                    Text("favorite_label")
                                        .foregroundColor(.red)
                                        .font(.subheadline.bold())
                                        .shadow(radius: 3)
                                }
                                .padding(.leading, 6)
                            }
                            Spacer()
                            Text("\(currentIndex+1)/\(assetIDs.count)")
                                .font(.footnote)
                                .padding(6)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(6)
                                .foregroundColor(.white)
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                    }
                    // 上方滑動教學區
                    .overlay(alignment: .top) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .foregroundColor(.white)
                                Text("swipe_left_delete")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .bold()
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text("swipe_right_keep")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .bold()
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 20)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(14)
                    }
                    // feedback 標示
                    .overlay(alignment: .center) {
                        if let text = feedbackText {
                            Text(text)
                                .font(.largeTitle.bold())
                                .padding(30)
                                .background(feedbackColor.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 16)
                                .opacity(feedbackOpacity)
                                .animation(.easeInOut(duration: 0.3), value: feedbackOpacity)
                                .transition(.scale)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { v in
                                if v.translation.width > 40 {
                                    withAnimation {
                                        feedbackText = NSLocalizedString("action_kept", comment: "")
                                        feedbackColor = .green
                                        feedbackOpacity = 1
                                    }
                                    localKeep.insert(currentIndex)
                                    goNextWithFeedback()
                                } else if v.translation.width < -40 {
                                    withAnimation {
                                        feedbackText = NSLocalizedString("action_deleted", comment: "")
                                        feedbackColor = .red
                                        feedbackOpacity = 1
                                    }
                                    localKeep.remove(currentIndex)
                                    goNextWithFeedback()
                                }
                            }
                    )
                }
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        Button {
                            withAnimation {
                                feedbackText = NSLocalizedString("action_deleted", comment: "")
                                feedbackColor = .red
                                feedbackOpacity = 1
                            }
                            localKeep.remove(currentIndex)
                            goNextWithFeedback()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("btn_delete")
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        Button {
                            withAnimation {
                                feedbackText = NSLocalizedString("action_kept", comment: "")
                                feedbackColor = .green
                                feedbackOpacity = 1
                            }
                            localKeep.insert(currentIndex)
                            goNextWithFeedback()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("btn_keep")
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("nav_title_advanced_review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("btn_cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("btn_done") {
                        let keptGlobals: Set<Int> = Set(
                            localKeep.compactMap { mapToGlobalIndex($0) }
                        )
                        onFinish(keptGlobals)
                        dismiss()
                    }
                }
            }
            .onAppear {
                localKeep = initiallyKept
                loadFavoriteStatus()
            }
            .onChange(of: currentIndex) { _ in
                loadFavoriteStatus()
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func goNextWithFeedback() {
        withAnimation { feedbackOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation { feedbackOpacity = 0 }
            if currentIndex < assetIDs.count - 1 {
                currentIndex += 1
            } else {
                let keptGlobals: Set<Int> = Set(
                    localKeep.compactMap { mapToGlobalIndex($0) }
                )
                onFinish(keptGlobals)
                dismiss()
            }
        }
    }

    private func loadFavoriteStatus() {
        guard assetIDs.indices.contains(currentIndex) else { isFavorite = false; return }
        let id = assetIDs[currentIndex]
        let fr = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fr.firstObject else { isFavorite = false; return }
        isFavorite = asset.isFavorite
    }
}

// --- ZoomableImageView/圖像載入與縮放 ---
struct ZoomableImageView: View {
    let assetID: String
    var placeholder: Color = .black
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in scale = value }
                            .onEnded { _ in
                                withAnimation(.spring()) { scale = max(1.0, min(scale, 4.0)) }
                            }
                    )
            } else {
                placeholder.overlay(ProgressView().tint(.white))
            }
        }
        .onAppear { loadLarge() }
        .onDisappear { scale = 1.0 }
    }

    private func loadLarge() {
        let key = "\(assetID)#large" as NSString
        if let cached = SimilarImagesView.imageCache.object(forKey: key) {
            self.image = cached
            return
        }
        let fr = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fr.firstObject else { return }
        let w = UIScreen.main.bounds.width * UIScreen.main.scale
        let target = CGSize(width: w, height: w)
        Task {
            let img = await requestImageAsyncOnce(asset, target: target, mode: .aspectFit)
            if let img {
                SimilarImagesView.imageCache.setObject(img, forKey: key)
                self.image = img
            }
        }
    }
}

func requestImageAsyncOnce(_ asset: PHAsset,
                           target: CGSize,
                           mode: PHImageContentMode = .aspectFill) async -> UIImage? {
    let opts = PHImageRequestOptions()
    opts.isSynchronous = false
    opts.deliveryMode  = .opportunistic
    opts.resizeMode    = .fast
    opts.isNetworkAccessAllowed = false
    return await withCheckedContinuation { cont in
        var resumed = false
        let reqID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: mode,
            options: opts
        ) { img, info in
            if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true ||
               (info?[PHImageErrorKey] as? NSError) != nil {
                if !resumed { resumed = true; cont.resume(returning: nil) }
                return
            }
            let degraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
            if !degraded {
                if !resumed { resumed = true; cont.resume(returning: img) }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 0)
            if Task.isCancelled && !resumed {
                PHImageManager.default().cancelImageRequest(reqID)
                resumed = true
                cont.resume(returning: nil)
            }
        }
    }
}

// --- 陣列安全取值 ---
extension Array {
    subscript(safe index: Int) -> Element? {
        (indices.contains(index)) ? self[index] : nil
    }
}
