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
    
    // 相似照片分組
    var grouped: [[Int]] {
        groupSimilarImages(pairs: similarPairs)
    }
    
    // 計算所有要保留的 index
    var allKeepIndices: Set<Int> {
        Set(selectedKeep.values.flatMap { $0 })
    }
    // 計算所有預計要刪除的 index
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
                            // 橫向滑動
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(group, id: \.self) { idx in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: images[idx])
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
                .padding(.bottom, 60) // 為下方 bar 預留空間
            }
            
            // --- 底部固定 bar ---
            VStack {
                Divider()
                HStack {
                    Text("保留 \(allKeepIndices.count) 張，預計刪除 \(allDeleteIndices.count) 張")
                        .font(.footnote)
                    Spacer()
                    Button(action: {
                        // TODO: 呼叫批次刪除流程
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
            // 預設每組只保留最前面一張
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


/// 分群邏輯保留原有
func groupSimilarImages(pairs: [(Int, Int)]) -> [[Int]] {
    var groups: [[Int]] = []
    var used = Set<Int>()

    for pair in pairs {
        let (a, b) = pair
        if used.contains(a) && used.contains(b) { continue }
        
        // 找到已經有包含 a 或 b 的 group
        var merged = false
        for i in 0..<groups.count {
            if groups[i].contains(a) {
                groups[i].append(b)
                used.insert(b)
                merged = true
                break
            } else if groups[i].contains(b) {
                groups[i].append(a)
                used.insert(a)
                merged = true
                break
            }
        }
        if !merged {
            groups.append([a, b])
            used.insert(a)
            used.insert(b)
        }
    }
    // 去重 + 排序
    for i in 0..<groups.count {
        groups[i] = Array(Set(groups[i])).sorted()
    }
    // 移除單一元素 group（不算重複）
    return groups.filter { $0.count > 1 }
}
