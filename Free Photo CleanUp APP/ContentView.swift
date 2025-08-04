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
    var assetIds: [String] // 新增！掃描時的asset順序
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
                    Button(action: {
                        // Haptic
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        // 執行掃描
                        startChunkScan(selected: nil)
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("一鍵掃描全部照片重複")
                            // 執行中才顯示轉圈圈
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                    .padding(.leading, 4)
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isProcessing ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .shadow(radius: 3)
                    }
                    .disabled(isProcessing)
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
        let categories = selected == nil ? PhotoCategory.allCases : [selected!]
        isProcessing = true

        Task {
            // 先重置每分類進度
            await MainActor.run {
                categories.forEach { processedCounts[$0] = 0 }
            }

            // 針對每個分類 individually 做 chunk scan
            for cat in categories {
                // 1. 拿到該分類所有 asset，去重並按 creationDate 排序
                let assets = await fetchAssetsAsync(for: cat)
                var seen = Set<String>()
                let uniqueAssets = assets
                    .filter { seen.insert($0.localIdentifier).inserted }
                    .sorted {
                        ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast)
                    }

                // 設定這個分類的總數（UI 進度條用）
                await MainActor.run {
                    categoryCounts[cat] = uniqueAssets.count
                }

                let windowSize = 50
                let chunkSize = 300
                var prevTailEmbs: [[Float]] = []
                var prevTailIds: [String] = []

                // 準備 globalIds 方便查找 global index
                let globalIds = uniqueAssets.map { $0.localIdentifier }

                // 2. 分 chunk 處理
                for chunkStart in stride(from: 0, to: uniqueAssets.count, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, uniqueAssets.count)
                    let chunkAssets = Array(uniqueAssets[chunkStart..<chunkEnd])

                    // 2.1 載圖 + 過濾
                    let pairs = await loadImagesWithIds(from: chunkAssets)   // (id, image) 對齊
                    let chunkIdsFiltered = pairs.map(\.id)
                    let images = pairs.map(\.image)

                    // 2.2 Embedding
                    let embs = await batchExtractEmbeddingsChunked(images: images)

                    // 2.3 window 比對
                    let allEmbs = prevTailEmbs + embs
                    let allIds  = prevTailIds + chunkIdsFiltered
                    var pairsIndices: [(Int, Int)] = []

                    for i in prevTailEmbs.count..<allEmbs.count {
                        for j in max(0, i - windowSize)..<i {
                            if cosineSimilarity(allEmbs[i], allEmbs[j]) >= 0.97 {
                                pairsIndices.append((j, i))
                            }
                        }
                    }

                    // 2.4 更新進度 & 分組
                    await MainActor.run {
                        // 更新進度
                        processedCounts[cat, default: 0] += chunkAssets.count

                        // 把 local-index 轉成 global-index
                        let globalPairs: [(Int, Int)] = pairsIndices.compactMap { pair in
                            let (localJ, localI) = pair
                            let idJ = allIds[localJ]
                            let idI = allIds[localI]
                            guard
                                let globalJ = globalIds.firstIndex(of: idJ),
                                let globalI = globalIds.firstIndex(of: idI)
                            else { return nil }
                            return (globalJ, globalI)
                        }

                        // 分組
                        let groups = groupSimilarImages(pairs: globalPairs)

                        // 存 ScanResult（同一批 assetIds）
                        scanResults[cat] = ScanResult(
                            date: Date(),
                            duplicateCount: (scanResults[cat]?.duplicateCount ?? 0) + groups.flatMap{$0}.count,
                            lastGroups:  (scanResults[cat]?.lastGroups  ?? []) + groups,
                            assetIds:    uniqueAssets.map { $0.localIdentifier }
                        )

                        saveScanResultsToLocal()
                    }

                    // 2.5 保留本 chunk 的尾端 windowSize 張給下一 chunk
                    if embs.count > windowSize {
                        prevTailEmbs = Array(embs.suffix(windowSize))
                        prevTailIds  = Array(chunkIdsFiltered.suffix(windowSize))
                    } else {
                        prevTailEmbs = embs
                        prevTailIds  = chunkIdsFiltered
                    }
                }
            }

            // 全部跑完
            await MainActor.run { isProcessing = false }
        }
    }
    
    
    // -- 只保留與你的embedding函數相容
    // 2) 順序正確、thread-safe 的 embedding 產生
    func batchExtractEmbeddingsChunked(
        images: [UIImage],
        chunkSize: Int = 300,
        maxConcurrent: Int = 2
    ) async -> [[Float]] {

        var allEmbeddings = Array(repeating: [Float](), count: images.count)

        for base in stride(from: 0, to: images.count, by: chunkSize) {
            let upper = min(base + chunkSize, images.count)
            var next = base
            while next < upper {
                let batchEnd = min(next + maxConcurrent, upper)
                await withTaskGroup(of: (Int, [Float]?).self) { group in
                    for idx in next..<batchEnd {
                        let img = images[idx]
                        group.addTask {
                            let emb = await extractEmbedding(from: img)
                            return (idx, emb)
                        }
                    }
                    for await (idx, emb) in group {
                        if let emb = emb { allEmbeddings[idx] = emb }
                        await MainActor.run { self.processingIndex += 1 }
                    }
                }
                next = batchEnd
            }
            autoreleasepool { }
        }
        return allEmbeddings
    }
    
    // 新的載圖 function：回傳成功的 (id, image)
    func loadImagesWithIds(from assets: [PHAsset]) async -> [(id: String, image: UIImage)] {
        let manager = PHImageManager.default()
        let req = PHImageRequestOptions()
        req.isSynchronous = false
        req.deliveryMode = .highQualityFormat

        var pairs = Array<(String, UIImage?)>(repeating: ("", nil), count: assets.count)
        await withTaskGroup(of: Void.self) { group in
            for (idx, asset) in assets.enumerated() {
                let id = asset.localIdentifier
                group.addTask {
                    await withCheckedContinuation { cont in
                        manager.requestImage(
                            for: asset,
                            targetSize: CGSize(width: 224, height: 224),
                            contentMode: .aspectFit,
                            options: req
                        ) { img, _ in
                            pairs[idx] = (id, img)
                            DispatchQueue.main.async { self.processingIndex += 1 }
                            cont.resume()
                        }
                    }
                }
            }
            await group.waitForAll()
        }
        // 過濾掉沒拿到圖的項目
        return pairs.compactMap { (id, img) in
            guard let img else { return nil }
            return (id, img)
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
        guard let res = scanResults[cat] else { return [] }
        let manager = PHImageManager.default()
        let req = PHImageRequestOptions()
        req.isSynchronous = true
        req.deliveryMode  = .highQualityFormat

        var out: [UIImage] = []
        for id in res.assetIds {
            let fr = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = fr.firstObject else { continue }
            var image: UIImage?
            manager.requestImage(for: asset,
                                 targetSize: CGSize(width: 224, height: 224),
                                 contentMode: .aspectFit,
                                 options: req) { img, _ in image = img }
            if let image { out.append(image) }
        }
        return out
    }

}




#Preview {
    ContentView()
}


