//
//  BlurryImagesEntryView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-16.
//


import SwiftUI
import Photos


/// 模糊照片：不分組，平鋪顯示 + 單張預覽 + 批次刪除
struct BlurryImagesEntryView: View {
    let category: PhotoCategory
    let blurryResult: BlurryScanResult

    // 只取出模糊那幾張的 assetIDs（保持原順序）
    private var blurryIDs: [String] {
        blurryResult.blurryIndices.compactMap { blurryResult.assetIds[safe: $0] }
    }

    // UI 狀態
    @State private var selectedIDs: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var previewIndex: Int? = nil // 用 index 讓預覽可左右切換

    // 縮圖格數（可依需要微調）
    private let columns: [GridItem] = [ GridItem(.adaptive(minimum: 90), spacing: 10) ]

    var body: some View {
        VStack(spacing: 0) {
            if blurryIDs.isEmpty {
                // 沒有模糊照片
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 44))
                        .foregroundColor(.green)
                    Text("no_blurry_photos") // 建議新增字串：繁:「沒有偵測到模糊照片」、英: "No blurry photos found"
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 平鋪縮圖
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(blurryIDs.enumerated()), id: \.element) { (idx, id) in
                            ZStack {
                                // 點縮圖 => 進入全螢幕預覽
                                ThumbnailView(
                                    assetID: id,
                                    isSelected: selectedIDs.contains(id),
                                    onTap: { previewIndex = idx }
                                )
                                .frame(width: 90, height: 90)

                                // 右上角：快速刪除
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button {
                                            // 單張刪除也走同一個流程（傳入單一 id）
                                            selectedIDs = [id]
                                            showDeleteConfirm = true
                                        } label: {
                                            Image(systemName: "trash.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.red)
                                                .shadow(radius: 1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(6)

                                // 左下角：選取切換
                                VStack {
                                    Spacer()
                                    HStack {
                                        Button {
                                            toggleSelect(id)
                                        } label: {
                                            Image(systemName: selectedIDs.contains(id) ? "checkmark.circle.fill" : "checkmark.circle")
                                                .font(.system(size: 20))
                                                .foregroundColor(selectedIDs.contains(id) ? .green : .white)
                                                .shadow(radius: 1)
                                                .padding(4)
                                                .background(Color.black.opacity(0.25))
                                                .clipShape(Circle())
                                        }
                                        Spacer()
                                    }
                                }
                                .padding(6)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        // 底部工具列 + Banner
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // 工具列
                HStack {
                    Button {
                        if selectedIDs.count == blurryIDs.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(blurryIDs)
                        }
                    } label: {
                        Text(selectedIDs.count == blurryIDs.count
                             ? NSLocalizedString("btn_deselect_all", comment: "") // 建議新增：繁:「全不選」、英:"Deselect All"
                             : NSLocalizedString("btn_select_all", comment: ""))  // 建議新增：繁:「全選」、英:"Select All"
                    }

                    Spacer()

                    Text("\(selectedIDs.count)/\(blurryIDs.count)")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        guard !selectedIDs.isEmpty else { return }
                        showDeleteConfirm = true
                    } label: {
                        Text(isDeleting
                             ? NSLocalizedString("btn_deleting", comment: "")
                             : NSLocalizedString("btn_delete_selected", comment: "")) // 建議新增：繁:「刪除已選」、英:"Delete Selected"
                            .bold()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background((selectedIDs.isEmpty || isDeleting) ? Color.gray : Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(selectedIDs.isEmpty || isDeleting)
                }
                .padding()
                .background(.ultraThinMaterial)

                // Banner
                BannerAdView(adUnitID: "ca-app-pub-9275380963550837/9201898058")
                    .frame(height: 50)
            }
        }
        .navigationTitle("nav_title_blurry_group")
        // 刪除確認
        .alert("confirm_delete_title", isPresented: $showDeleteConfirm) {
            Button("btn_cancel", role: .cancel) {}
            Button("btn_delete", role: .destructive) { performDelete(Array(selectedIDs)) }
        } message: {
            Text(String(format: NSLocalizedString("confirm_delete_msg", comment: ""),
                        selectedIDs.count))
        }
        // 刪除錯誤
        .alert("delete_failed_title",
               isPresented: Binding(get: { deleteError != nil }, set: { _ in deleteError = nil })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        // 全螢幕預覽（可左右切換）
        .fullScreenCover(item: Binding(
            get: { previewIndex.map { PreviewToken(index: $0) } },
            set: { token in previewIndex = token?.index }
        )) { token in
            BlurryPreviewPager(
                ids: blurryIDs,
                startIndex: token.index,
                onClose: { previewIndex = nil },
                onDeleteCurrent: { currentID in
                    // 刪當前，並同步移除選取 & 更新索引
                    performDelete([currentID])
                }
            )
        }
        .onAppear {
            selectedIDs.removeAll()
        }
    }

    private func toggleSelect(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func performDelete(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count > 0 else { return }
        isDeleting = true
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(fetch as NSFastEnumeration)
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                isDeleting = false
                if let error = error {
                    deleteError = error.localizedDescription
                    return
                }
                // 刪除成功：把本地列表中的 id 移除，選取集也同步移除
                let toDelete = Set(ids)
                // 從 selectedIDs 移除
                selectedIDs.subtract(toDelete)
                // 從 blurryResult.assetIds/blurryIndices 的對應清單不會自動改，
                // 但我們這個畫面是用 blurryIDs 平鋪，這裡直接用「過濾後的陣列重建」最省事：
                // 方案：把剩餘 id 重新打到 previewIndex
                // 讓預覽回來時不會指到已刪除的那張
                if let current = previewIndex {
                    // 重新定位到最接近的下一張
                    let remaining = blurryIDs.filter { !toDelete.contains($0) }
                    if remaining.isEmpty {
                        previewIndex = nil
                    } else {
                        let clamped = min(current, max(remaining.count - 1, 0))
                        previewIndex = clamped
                    }
                }
            }
        })
    }

    private struct PreviewToken: Identifiable {
        let id = UUID()
        let index: Int
    }
}

/// 全螢幕預覽（左右切換 + 刪除當前）
private struct BlurryPreviewPager: View {
    let ids: [String]
    let startIndex: Int
    let onClose: () -> Void
    let onDeleteCurrent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(ids: [String], startIndex: Int, onClose: @escaping () -> Void, onDeleteCurrent: @escaping (String) -> Void) {
        self.ids = ids
        self.startIndex = startIndex
        self.onClose = onClose
        self.onDeleteCurrent = onDeleteCurrent
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if ids.indices.contains(index) {
                    ZoomableImageView(assetID: ids[index], placeholder: .black)
                        .background(Color.black)
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { v in
                                    if v.translation.width < -40 { goNext() }
                                    if v.translation.width >  40 { goPrev() }
                                }
                        )
                } else {
                    ProgressView().tint(.white)
                }

                // 左右切換按鈕（可選）
                HStack {
                    Button(action: goPrev) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.9))
                    }.padding(.leading, 16)
                    Spacer()
                    Button(action: goNext) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.9))
                    }.padding(.trailing, 16)
                }
                .padding(.bottom, 40)
                .opacity(ids.count > 1 ? 1 : 0)
                .allowsHitTesting(ids.count > 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                        dismiss()
                    } label: {
                        Text("btn_cancel") // 已有
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("\(min(index+1, ids.count))/\(ids.count)")
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        if ids.indices.contains(index) {
                            onDeleteCurrent(ids[index])
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func goNext() {
        guard !ids.isEmpty else { return }
        index = min(index + 1, ids.count - 1)
    }

    private func goPrev() {
        guard !ids.isEmpty else { return }
        index = max(index - 1, 0)
    }
}



