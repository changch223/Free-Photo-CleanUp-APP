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

    @State private var selectedKeep: [Int: Set<Int>] = [:]

    // 用 pairs group 成 [[Int]]
    var grouped: [[Int]] {
        groupSimilarImages(pairs: similarPairs)
    }
    var allKeepIndices: Set<Int> {
        Set(selectedKeep.values.flatMap { $0 })
    }
    var allDeleteIndices: [Int] {
        grouped.flatMap { group in
            let groupIdx = grouped.firstIndex(of: group) ?? 0
            return group.filter { !(selectedKeep[groupIdx]?.contains($0) ?? false) }
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
                            Text("已選擇保留：\(selectedKeep[groupIdx]?.count ?? 0) / \(group.count)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.leading, 10)
                        }
                    }
                }
                .padding(.top)
                .padding(.bottom, 60)
            }
            // 底部操作
            VStack {
                Divider()
                HStack {
                    Text("保留 \(allKeepIndices.count) 張，預計刪除 \(allDeleteIndices.count) 張")
                        .font(.footnote)
                    Spacer()
                    Button(action: {
                        print("批次刪除 index:", allDeleteIndices)
                    }) {
                        Text("批次刪除")
                            .fontWeight(.bold)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(allDeleteIndices.isEmpty ? Color.gray : Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(allDeleteIndices.isEmpty)
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
            // 預設每組選保留第一張
            var dict: [Int: Set<Int>] = [:]
            for (i, group) in grouped.enumerated() {
                if let first = group.first {
                    dict[i] = [first]
                }
            }
            selectedKeep = dict
        }
    }
}

// 小圖載入 cell
struct ThumbnailView: View {
    let assetID: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var thumb: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = thumb {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5) // loading placeholder
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
            .onAppear(perform: loadThumbnail)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .offset(x: -5, y: 5)
            }
        }
    }

    func loadThumbnail() {
        guard !assetID.isEmpty else { return }
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
        guard let asset = asset else { return }
        let manager = PHCachingImageManager.default()
        let opts = PHImageRequestOptions()
        opts.isSynchronous = false
        opts.deliveryMode = .fastFormat

        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 80 * UIScreen.main.scale, height: 80 * UIScreen.main.scale),
                             contentMode: .aspectFill,
                             options: opts) { img, _ in
            DispatchQueue.main.async {
                self.thumb = img
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
