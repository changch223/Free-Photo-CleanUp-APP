//
//  SimilarImagesView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-30.
//

import SwiftUI

struct SimilarImagesView: View {
    let similarPairs: [(Int, Int)]
    let images: [UIImage]

    @State private var selectedKeep: [Int: Set<Int>] = [:]  // groupIdx: Set<imageIndex>

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
                VStack(spacing: 18) {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { (groupIdx, group) in
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(group, id: \.self) { idx in
                                        ZStack(alignment: .topTrailing) {
                                            if let img = images[safe: idx] {
                                                Image(uiImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 80, height: 80)
                                                    .clipped()
                                                    .cornerRadius(12)
                                                    .shadow(radius: 2)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(selectedKeep[groupIdx]?.contains(idx) == true ? Color.green : Color.gray.opacity(0.3), lineWidth: 3)
                                                    )
                                                    .onTapGesture {
                                                        if selectedKeep[groupIdx]?.contains(idx) == true {
                                                            selectedKeep[groupIdx]?.remove(idx)
                                                        } else {
                                                            selectedKeep[groupIdx, default: []].insert(idx)
                                                        }
                                                    }
                                            }
                                            if selectedKeep[groupIdx]?.contains(idx) == true {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .offset(x: -5, y: 5)
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
            // 底部固定 bar
            VStack {
                Divider()
                HStack {
                    Text("保留 \(allKeepIndices.count) 張，預計刪除 \(allDeleteIndices.count) 張")
                        .font(.footnote)
                    Spacer()
                    Button(action: {
                        print("批次刪除這些 index:", allDeleteIndices)
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
            print("SimilarImagesView images.count:", images.count)
            print("SimilarImagesView similarPairs:", similarPairs)
            print("SimilarImagesView grouped:", grouped)
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

// --- 陣列安全取值小助手（避免 index 越界 crash） ---
extension Array {
    subscript(safe index: Int) -> Element? {
        (indices.contains(index)) ? self[index] : nil
    }
}


