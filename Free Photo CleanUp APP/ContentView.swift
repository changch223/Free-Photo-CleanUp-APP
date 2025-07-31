//
//  ContentView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-28.
//

//  ContentView.swift
//  Free Photo CleanUp APP

import SwiftUI
import SwiftData
import Photos

enum PhotoCategory: String, CaseIterable, Identifiable {
    case photo = "照片"
    case selfie = "自拍"
    case portrait = "人像"
    case screenshot = "銀幕截圖"
    case video = "影片"
    case screenRecording = "螢幕錄影"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    @State private var images: [UIImage] = []
    @State private var similarPairs: [(Int, Int)] = []
    @State private var showResults = false
    @State private var isProcessing = false
    @State private var showAlert = false
    @State private var selectedCategory: PhotoCategory = .selfie
    @State private var categoryCounts: [PhotoCategory: Int] = [:]
    @State private var processingIndex: Int = 0
    @State private var processingTotal: Int = 0
    
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("分類", selection: $selectedCategory) {
                    ForEach(PhotoCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Text("本分類共 \(categoryCounts[selectedCategory] ?? 0) 張照片")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("載入分類圖片") {
                    fetchAssets(for: selectedCategory) { assets in
                        loadImages(from: assets)
                        categoryCounts[selectedCategory] = assets.count
                    }
                }
                
                ScrollView {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3)) {
                        ForEach(images.indices, id: \.self) { idx in
                            Image(uiImage: images[idx])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                        }
                    }.padding()
                }
                
                if isProcessing {
                    ProgressView("Analyzing photos...")
                        .padding(.bottom, 8)
                    if processingTotal > 0 {
                        let percent = Int(Double(processingIndex) / Double(processingTotal) * 100)
                        Text("進度：\(processingIndex)/\(processingTotal)（\(percent)%）")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                } else {
                    Button("Start Similarity Check") {
                        isProcessing = true
                        fetchFirst100Images { fetchedImages in
                            print("✅ 已載入圖片數量：\(fetchedImages.count)")
                            
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
            .onAppear {
                loadAllCategoryCounts()
            }
            .navigationTitle("Free Photo CleanUp")
            .padding()
            .alert("未找到任何圖片，請確認您的相簿有照片並允許取用權限。", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }
    
    // MARK: - 最終分類邏輯
    func fetchAssets(for category: PhotoCategory, completion: @escaping ([PHAsset]) -> Void) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        switch category {
        case .selfie:
            // iOS 內建「自拍」
            let collection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumSelfPortraits,
                options: nil)
            var arr: [PHAsset] = []
            collection.enumerateObjects { col, _, _ in
                let assets = PHAsset.fetchAssets(in: col, options: options)
                assets.enumerateObjects { asset, _, _ in arr.append(asset) }
            }
            completion(arr)
            
        case .portrait:
            // 景深相片
            options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", PHAssetMediaSubtype.photoDepthEffect.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
            var arr: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
            completion(arr)
            
        case .screenshot:
            // 銀幕截圖
            options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
            var arr: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
            completion(arr)
            
        case .screenRecording:
            // 螢幕錄影 (官方 bitmask 524288)
            options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", 524288)
            let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
            var arr: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
            completion(arr)
            
        case .video:
            // 影片（排除螢幕錄影）
            let allVideos = PHAsset.fetchAssets(with: .video, options: options)
            var arr: [PHAsset] = []
            allVideos.enumerateObjects { asset, _, _ in
                if asset.mediaSubtypes.rawValue & 524288 == 0 {
                    arr.append(asset)
                }
            }
            completion(arr)
            
        case .photo:
            // 取得所有 selfie asset identifier
            let selfieCollection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
            var selfieIds: Set<String> = []
            selfieCollection.enumerateObjects { col, _, _ in
                let selfieAssets = PHAsset.fetchAssets(in: col, options: nil)
                selfieAssets.enumerateObjects { asset, _, _ in
                    selfieIds.insert(asset.localIdentifier)
                }
            }
            
            // 取得所有照片，排除 selfie/portrait/screenshot
            let allImages = PHAsset.fetchAssets(with: .image, options: options)
            var arr: [PHAsset] = []
            allImages.enumerateObjects { asset, _, _ in
                let isSelfie = selfieIds.contains(asset.localIdentifier)
                let isPortrait = asset.mediaSubtypes.contains(.photoDepthEffect)
                let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                if !isSelfie && !isPortrait && !isScreenshot {
                    arr.append(asset)
                }
            }
            completion(arr)
        }
    }
    
    
    
    func loadImages(from assets: [PHAsset]) {
        images.removeAll()
        let manager = PHImageManager.default()
        let reqOpts = PHImageRequestOptions()
        reqOpts.isSynchronous = false
        reqOpts.deliveryMode = .highQualityFormat
        
        for asset in assets {
            manager.requestImage(for: asset, targetSize: CGSize(width: 200, height: 200),
                                 contentMode: .aspectFill, options: reqOpts) { img, _ in
                if let img {
                    DispatchQueue.main.async { images.append(img) }
                }
            }
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
    
    func loadAllCategoryCounts() {
        for category in PhotoCategory.allCases {
            fetchAssets(for: category) { assets in
                DispatchQueue.main.async {
                    categoryCounts[category] = assets.count
                }
            }
        }
    }
    
    func processImages() {
        var embeddings: [[Float]] = Array(repeating: [], count: images.count)
        let group = DispatchGroup()
        processingTotal = images.count
        processingIndex = 0

        for (index, img) in images.enumerated() {
            group.enter()
            extractEmbedding(from: img) { vector in
                if let v = vector {
                    embeddings[index] = v
                } else {
                    print("❌ 第 \(index + 1) 張圖片向量提取失敗")
                }
                // ⬇️ 這裡才是每張完成時增加進度
                DispatchQueue.main.async {
                    processingIndex += 1
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            print("📦 向量樣本：\(embeddings.first ?? [])")
            print("🧠 相似度計算開始")
            similarPairs = findSimilarPairs(embeddings: embeddings, threshold: 0.97, window: 50)
            print("📸 找到相似圖片組合數：\(similarPairs.count)")
            for pair in similarPairs {
                print("🔗 \(pair.0) 與 \(pair.1) 是相似圖片")
            }
            showResults = true
            isProcessing = false
            processingIndex = 0
            processingTotal = 0
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
