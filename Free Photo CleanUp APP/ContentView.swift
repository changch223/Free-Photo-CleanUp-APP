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
    case selfie = "自拍"
    case live = "原況照片"
    case portrait = "人像"
    case timelapse = "縮時攝影"
    case slow = "慢動作"
    case burst = "連拍"
    case screenshot = "截圖"
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
                
                Button("載入分類圖片") {
                    fetchAssets(for: selectedCategory) { assets in
                        loadImages(from: assets)
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
            .navigationTitle("Free Photo CleanUp")
            .padding()
            .alert("未找到任何圖片，請確認您的相簿有照片並允許取用權限。", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    func fetchAssets(for category: PhotoCategory, completion: @escaping ([PHAsset]) -> Void) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        switch category {
        case .selfie:
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
            
        case .burst:
            options.predicate = NSPredicate(format: "representsBurst == YES")
            fallthrough
            
        case .live, .portrait, .timelapse, .slow, .screenshot, .screenRecording:
            // 原有 bitmask predicate 方法
            var mask: UInt = 0
            switch category {
            case .live:
                mask = PHAssetMediaSubtype.photoLive.rawValue
            case .portrait:
                mask = PHAssetMediaSubtype.photoDepthEffect.rawValue
            case .timelapse:
                mask = PHAssetMediaSubtype.videoTimelapse.rawValue
            case .slow:
                mask = PHAssetMediaSubtype.videoHighFrameRate.rawValue
            case .screenshot:
                mask = PHAssetMediaSubtype.photoScreenshot.rawValue
            case .screenRecording:
                mask = 524288
            default:
                break
            }
            if mask > 0 {
                options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", Int(mask))
            }
            let mediaType: PHAssetMediaType =
            (category == .timelapse || category == .slow || category == .screenRecording) ? .video : .image
            let fetchResult = PHAsset.fetchAssets(with: mediaType, options: options)
            var arr: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
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
            print("🧠 相似度計算開始")

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
