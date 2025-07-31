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
    
    @State private var selectedKeep: [Int: Set<Int>] = [:]  // groupIndex: Set<imageIndex>
    
    var grouped: [[Int]] {
        groupSimilarImages(pairs: similarPairs)
    }
    
    var body: some View {
        List {
            ForEach(Array(grouped.enumerated()), id: \.offset) { (groupIdx, group) in
                VStack(alignment: .leading) {
                    HStack {
                        ForEach(group, id: \.self) { idx in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: images[idx])
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .border(selectedKeep[groupIdx]?.contains(idx) == true ? Color.green : Color.clear, width: 2)
                                    .onTapGesture {
                                        // 選擇保留
                                        if selectedKeep[groupIdx]?.contains(idx) == true {
                                            selectedKeep[groupIdx]?.remove(idx)
                                        } else {
                                            // 只允許多選（可改成只選一個）
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
                    HStack {
                        Text("保留: \(selectedKeep[groupIdx]?.map { "\($0+1)" }.joined(separator: ", ") ?? "")")
                            .font(.caption)
                        Spacer()
                        Button("刪除此組未勾選照片") {
                            let keeps = selectedKeep[groupIdx] ?? []
                            let toDelete = group.filter { !keeps.contains($0) }
                            // 這裡觸發你的刪除流程（記錄 index or asset identifier 再呼叫 Photos 刪除）
                            print("要刪除這組:", toDelete)
                        }
                        .foregroundColor(.red)
                        .disabled((selectedKeep[groupIdx]?.count ?? 0) == group.count)
                    }
                }
                .padding(.vertical, 4)
            }
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
