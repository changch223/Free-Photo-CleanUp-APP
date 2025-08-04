//
//  ContentView.swift
//  Free Photo CleanUp APP
//

import SwiftUI
import Photos

enum PhotoCategory: String, CaseIterable, Identifiable, Codable {
    case photo = "照片"
    case selfie = "自拍"
    case portrait = "人像"
    case screenshot = "銀幕截圖"
    var id: String { rawValue }
}

struct ScanResult: Codable {
    var date: Date
    var duplicateCount: Int
    var lastGroups: [[Int]]
}

struct ContentView: View {
    // 狀態
    @State private var categoryCounts: [PhotoCategory: Int] = [:]  // 總數
    @State private var processedCounts: [PhotoCategory: Int] = [:] // 已掃描數
    @State private var scanResults: [PhotoCategory: ScanResult] = [:]
    @State private var selectedCategories: Set<PhotoCategory> = []
    @State private var isProcessing = false
    @State private var processingIndex = 0
    @State private var processingTotal = 0
    
    // --- 本地快取 key
    let scanResultsKey = "ScanResults"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Free Photo CleanUp")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 24)
                    Text("幫你找出手機裡的重複照片，一鍵清理釋放空間")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.bottom, 16)
                    Button(action: { startChunkScan(selected: nil) }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("一鍵掃描全部照片重複")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .shadow(radius: 3)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("選擇要掃描的分類（可多選）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(PhotoCategory.allCases, id: \.self) { cat in
                                Button(action: {
                                    if selectedCategories.contains(cat) {
                                        selectedCategories.remove(cat)
                                    } else {
                                        selectedCategories.insert(cat)
                                    }
                                }) {
                                    VStack(spacing: 2) {
                                        Text(cat.rawValue)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(selectedCategories.contains(cat) ? Color.orange : Color(.systemGray5))
                                            .foregroundColor(selectedCategories.contains(cat) ? .white : .primary)
                                            .cornerRadius(20)
                                        let scanned = processedCounts[cat] ?? 0
                                        let total = categoryCounts[cat] ?? 0
                                        Text("已掃描 \(scanned) / \(total) 張")
                                        ProgressView(value: Double(scanned), total: Double(max(total, 1)))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Button(action: {
                        //startScanMultiple(selected: Array(selectedCategories))
                    }) {
                        Text("掃描所選分類")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedCategories.isEmpty ? Color(.systemGray3) : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(selectedCategories.isEmpty)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    
                    // 列出所有分類進度 & 結果
                    VStack(spacing: 10) {
                        ForEach(PhotoCategory.allCases, id: \.self) { cat in
                            let scanned = processedCounts[cat] ?? 0
                            let total = categoryCounts[cat] ?? 0
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(cat.rawValue)
                                    Text("已掃描 \(scanned) / \(total) 張").font(.caption).foregroundColor(.secondary)
                                    ProgressView(value: Double(scanned), total: Double(max(total, 1)))
                                        .frame(width: 130)
                                }
                                Spacer()
                                if let res = scanResults[cat], res.duplicateCount > 0 {
                                    Text("重複 \(res.duplicateCount) 張").foregroundColor(.red).font(.caption)
                                    NavigationLink("查看重複") {
                                        let pairs = pairsFromGroups(res.lastGroups)
                                        let imgs = loadImagesForCategory(cat)
                                        SimilarImagesView(similarPairs: pairs, images: imgs)
                                    }
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                                } else {
                                    Text("無重複").foregroundColor(.secondary).font(.caption)
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                    .padding(.top, 8)
                    
                    // --- 進度條 UI（全域）
                    let totalProcessed = processedCounts.values.reduce(0, +)
                    let totalCount = categoryCounts.values.reduce(0, +)
                    if isProcessing {
                        VStack {
                            Text("總進度 \(totalProcessed)/\(totalCount)")
                            ProgressView(value: Double(totalProcessed), total: Double(max(totalCount, 1)))
                        }.padding()
                    }
                    Spacer()
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear { Task { await refreshCategoryCounts() } }
        }
    }

    // MARK: - Chunk 掃描核心流程
    func startChunkScan(selected: PhotoCategory?) {
        let categories: [PhotoCategory] = selected == nil ? PhotoCategory.allCases : [selected!]
        isProcessing = true
        processingIndex = 0

        Task {
            var allAssetsByCategory: [PhotoCategory: [PHAsset]] = [:]
            for cat in categories {
                let assets = await fetchAssetsAsync(for: cat)
                allAssetsByCategory[cat] = assets
                await MainActor.run {
                    processedCounts[cat] = 0
                }
            }

            let allAssets = allAssetsByCategory.values.flatMap { $0 }
            let assetDict = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.localIdentifier, $0) })
            let uniqueAssets = Array(assetDict.values)
            let totalCount = uniqueAssets.count
            processingTotal = totalCount

            let chunkSize = 300
            var prevTailEmbeddings: [[Float]] = []
            var prevTailAssetIds: [String] = []

            for chunkStart in stride(from: 0, to: totalCount, by: chunkSize) {
                let chunkEnd = min(chunkStart+chunkSize, totalCount)
                let chunkAssets = Array(uniqueAssets[chunkStart..<chunkEnd])
                let chunkAssetIdsNow = chunkAssets.map { $0.localIdentifier }
                // 1. 分批載入圖片
                let images = await loadImagesWithProgress(from: chunkAssets)
                // 2. 分批embedding，限制最多2個同時進行
                let embeddings = await batchExtractEmbeddingsChunked(images: images, chunkSize: chunkSize)

                // 3. 合併tail (for sliding window)
                let window = 50
                let allEmbeddings: [[Float]] = prevTailEmbeddings + embeddings
                let allAssetIds: [String] = prevTailAssetIds + chunkAssetIdsNow

                // 4. 分批比對
                var pairs: [(Int, Int)] = []
                let totalThis = allEmbeddings.count
                let startIdx = prevTailEmbeddings.count

                for i in startIdx..<totalThis {
                    let embI = allEmbeddings[i]
                    let startJ = max(0, i-window)
                    for j in startJ..<i {
                        let embJ = allEmbeddings[j]
                        let sim = cosineSimilarity(embI, embJ)
                        if sim >= 0.97 {
                            pairs.append((j, i))
                        }
                    }
                    await MainActor.run { processingIndex += 1 }
                }

                // 5. 統計分類結果/更新 cache/進度
                await MainActor.run {
                    for cat in categories {
                        guard let assets = allAssetsByCategory[cat], !assets.isEmpty else { continue }
                        let catAssetIds = Set(assets.map { $0.localIdentifier })
                        let chunkProcessed = chunkAssetIdsNow.filter { catAssetIds.contains($0) }.count
                        let prev = processedCounts[cat] ?? 0
                        processedCounts[cat] = prev + chunkProcessed
                        
                        let catPairs = pairs.filter { catAssetIds.contains(allAssetIds[$0.0]) && catAssetIds.contains(allAssetIds[$0.1]) }
                        let groups = groupSimilarImages(pairs: catPairs)
                        let dupCount = groups.flatMap { $0 }.count
                        let oldRes = scanResults[cat]
                        let oldGroups = oldRes?.lastGroups ?? []
                        let oldDup = oldRes?.duplicateCount ?? 0
                        scanResults[cat] = ScanResult(
                            date: Date(),
                            duplicateCount: oldDup + dupCount,
                            lastGroups: oldGroups + groups
                        )
                        saveScanResultsToLocal()
                    }
                }

                // 6. 保留chunk尾端window for sliding window
                if embeddings.count > window {
                    prevTailEmbeddings = Array(embeddings.suffix(window))
                    prevTailAssetIds = Array(chunkAssetIdsNow.suffix(window))
                } else {
                    prevTailEmbeddings = embeddings
                    prevTailAssetIds = chunkAssetIdsNow
                }
            }
            isProcessing = false
        }
    }

    // -- 只保留與你的embedding函數相容
    func batchExtractEmbeddingsChunked(images: [UIImage], chunkSize: Int = 300) async -> [[Float]] {
        var allEmbeddings: [[Float]] = []
        let semaphore = DispatchSemaphore(value: 2)  // 控制最多2 pipeline
        let total = images.count

        for chunkStart in stride(from: 0, to: total, by: chunkSize) {
            let chunk = Array(images[chunkStart..<min(chunkStart+chunkSize, total)])
            for img in chunk {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        semaphore.wait()
                        Task {
                            if let emb = await extractEmbedding(from: img) {
                                allEmbeddings.append(emb)
                            }
                            await MainActor.run { self.processingIndex += 1 }
                            semaphore.signal()
                            continuation.resume()
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }
        return allEmbeddings
    }

    func loadImagesWithProgress(from assets: [PHAsset]) async -> [UIImage] {
        await withCheckedContinuation { continuation in
            var loadedImages: [UIImage] = []
            let manager = PHImageManager.default()
            let reqOpts = PHImageRequestOptions()
            reqOpts.isSynchronous = false
            reqOpts.deliveryMode = .highQualityFormat

            let group = DispatchGroup()
            for asset in assets {
                group.enter()
                manager.requestImage(for: asset, targetSize: CGSize(width: 224, height: 224),
                                     contentMode: .aspectFit, options: reqOpts) { img, _ in
                    if let img = img { loadedImages.append(img) }
                    DispatchQueue.main.async { self.processingIndex += 1 }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                continuation.resume(returning: loadedImages)
            }
        }
    }

    func fetchAssetsAsync(for category: PhotoCategory) async -> [PHAsset] {
        await withCheckedContinuation { continuation in
            fetchAssets(for: category) { assets in
                continuation.resume(returning: assets)
            }
        }
    }

    func pairsFromGroups(_ groups: [[Int]]) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        for group in groups {
            for i in 0..<(group.count - 1) {
                pairs.append((group[i], group[i+1]))
            }
        }
        return pairs
    }

    func refreshCategoryCounts() async {
        for cat in PhotoCategory.allCases {
            let assets = await fetchAssetsAsync(for: cat)
            await MainActor.run { categoryCounts[cat] = assets.count }
        }
    }

    func saveScanResultsToLocal() {
        if let data = try? JSONEncoder().encode(scanResults) {
            UserDefaults.standard.set(data, forKey: scanResultsKey)
        }
    }
    
    // ---- 取得該分類資產 ----
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
        case .portrait:
            options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", PHAssetMediaSubtype.photoDepthEffect.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
            var arr: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
            completion(arr)
        case .screenshot:
            options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
            var arr: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
            completion(arr)
        case .photo:
            let selfieCollection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
            var selfieIds: Set<String> = []
            selfieCollection.enumerateObjects { col, _, _ in
                let selfieAssets = PHAsset.fetchAssets(in: col, options: nil)
                selfieAssets.enumerateObjects { asset, _, _ in
                    selfieIds.insert(asset.localIdentifier)
                }
            }
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
    func loadImagesForCategory(_ cat: PhotoCategory) -> [UIImage] {
        return loadImagesFromDisk(for: cat)
    }
}




#Preview {
    ContentView()
}


