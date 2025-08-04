//
//  SimilarImagesView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-30.
//

import SwiftUI
import Photos

struct SimilarImagesView: View {
    let similarPairs: [(Int, Int)]
    let assetIds: [String]

    static var imageCache = NSCache<NSString, UIImage>()

    @State private var selectedKeep: [Int: Set<Int>] = [:]
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var reviewingGroupIndex: Int? = nil

    // 新增：記錄所有已刪除的 global index
    @State private var deletedIndices: Set<Int> = []

    // 只顯示未被刪除的 group
    var grouped: [[Int]] {
        groupSimilarImages(pairs: similarPairs)
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
                                Text("已選擇保留：\(selectedKeep[groupIdx]?.count ?? 0) / \(group.count)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Button {
                                    reviewingGroupIndex = groupIdx
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "rectangle.and.magnifyingglass")
                                        Text("進階篩選")
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
                .padding(.bottom, 60)
            }

            VStack {
                Divider()
                HStack {
                    Text("保留 \(allKeepIndices.count) 張，預計刪除 \(allDeleteIndices.count) 張")
                        .font(.footnote)
                    Spacer()
                    Button(action: { showDeleteConfirm = true }) {
                        Text(isDeleting ? "刪除中…" : "批次刪除")
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
                .cornerRadius(16)
                .shadow(radius: 5)
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 0)
        }
        .navigationTitle("連續相似群組")
        .onAppear {
            // (1) 先用「第一張」建立預設（極快）
            var initial: [Int: Set<Int>] = [:]
            for (i, group) in groupSimilarImages(pairs: similarPairs).enumerated() {
                if let first = group.first { initial[i] = [first] }
            }
            selectedKeep = initial

            // (2) 背景提升：有最愛就全部加進預設
            Task.detached { await pickAllFavoritesAsDefaultKeep() }
        }
        .alert("確認刪除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("刪除", role: .destructive) { performDelete() }
        } message: {
            Text("確定要刪除 \(allDeleteIndices.count) 張照片嗎？刪除後將移至「最近刪除」。")
        }
        .alert("刪除失敗", isPresented: Binding(get: { deleteError != nil }, set: { _ in deleteError = nil })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        // 進階篩選全螢幕
        .fullScreenCover(item: Binding(
            get: {
                reviewingGroupIndex.map { ReviewToken(id: $0) }
            },
            set: { token in
                reviewingGroupIndex = token?.id
            }
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
                onCancel: { reviewingGroupIndex = nil }
            )
        }
    }

    // 只要是最愛都加到保留（全 group 內檢查）
    private func pickAllFavoritesAsDefaultKeep() async {
        await withTaskGroup(of: (Int, Set<Int>).self) { group in
            for (gIdx, members) in groupSimilarImages(pairs: similarPairs).enumerated() {
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

    // 新增：用 deletedIndices 馬上讓被刪除照片消失
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
                // 1. 刪除成功，直接記錄下已刪除 index，所有 UI 自動消失
                self.deletedIndices.formUnion(indicesToDelete)
                // 2. selectedKeep 也要移除這些 index，避免資料殘留
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

    func loadThumbnail() {
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
    func fetchFavoriteStatus() {
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
                                    Text("最愛")
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
                                Text("向左滑=刪除")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .bold()
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text("保留=向右滑")
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
                                        feedbackText = "已保留"
                                        feedbackColor = .green
                                        feedbackOpacity = 1
                                    }
                                    localKeep.insert(currentIndex)
                                    goNextWithFeedback()
                                } else if v.translation.width < -40 {
                                    withAnimation {
                                        feedbackText = "已刪除"
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
                                feedbackText = "已刪除"
                                feedbackColor = .red
                                feedbackOpacity = 1
                            }
                            localKeep.remove(currentIndex)
                            goNextWithFeedback()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("刪除")
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        Button {
                            withAnimation {
                                feedbackText = "已保留"
                                feedbackColor = .green
                                feedbackOpacity = 1
                            }
                            localKeep.insert(currentIndex)
                            goNextWithFeedback()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("保留")
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
            .navigationTitle("進階篩選")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
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
