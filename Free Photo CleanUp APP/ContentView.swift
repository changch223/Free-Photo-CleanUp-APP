//
//  ContentView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-28.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    @State private var images: [UIImage] = []
    @State private var similarPairs: [(Int, Int)] = []
    @State private var showResults = false
    @State private var isProcessing = false
    @State private var showAlert = false  // ✅ 用於顯示錯誤提示
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 20) {
                if isProcessing {
                    ProgressView("Analyzing photos...")
                } else {
                    Button("Start Similarity Check") {
                        isProcessing = true
                        fetchFirst100Images { fetchedImages in
                            print("✅ 已載入圖片數量：\(fetchedImages.count)") // ✅ 圖片數量 debug

                            if fetchedImages.isEmpty {
                                isProcessing = false
                                showAlert = true
                                return
                            }
                            images = fetchedImages
                            processImages()
                        }
                    }
                }

                if showResults {
                    NavigationLink("Show Similar Images", destination: SimilarImagesView(similarPairs: similarPairs, images: images))
                }
            }
            .navigationTitle("Free Photo CleanUp")
            .padding()
            .alert("未找到任何圖片，請確認您的相簿有照片並允許取用權限。", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }
    
    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
    
    func processImages() {
        var embeddings: [[Float]] = Array(repeating: [], count: images.count)
        let group = DispatchGroup()
        
        for (index, img) in images.enumerated() {
            print("🔄 開始處理第 \(index + 1) 張圖")
            
            group.enter()
            extractEmbedding(from: img) { vector in
                if let v = vector {
                    embeddings[index] = v
                } else {
                    print("❌ 第 \(index + 1) 張圖片向量提取失敗")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            print("📦 向量樣本：\(embeddings.first ?? [])")
            print("🧠 相似度計算開始") // ✅ 新增這一行
            
            similarPairs = findSimilarPairs(embeddings: embeddings, threshold: 0.97)
            
            print("📸 找到相似圖片組合數：\(similarPairs.count)")
            for pair in similarPairs {
                print("🔗 \(pair.0) 與 \(pair.1) 是相似圖片")
            }
            
            showResults = true
            isProcessing = false
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
