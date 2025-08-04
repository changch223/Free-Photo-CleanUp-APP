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
    case screenshot = "螢幕截圖"
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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(PhotoCategory.allCases, id: \.self) { cat in
                                    Button(action: {
                                        if selectedCategories.contains(cat) {
                                            selectedCategories.remove(cat)
                                        } else {
                                            selectedCategories.insert(cat)
                                        }
                                    }) {
                                        Text(cat.rawValue)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 12)
                                            .background(selectedCategories.contains(cat) ? Color.orange : Color(.systemGray5))
                                            .foregroundColor(selectedCategories.contains(cat) ? .white : .primary)
                                            .cornerRadius(24)
                                    }
                                    .buttonStyle(.plain)
                                }

                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 8)
                    }
                    
                    Button(action: {
                        startScanMultiple(selected: Array(selectedCategories))
                    }) {
                        HStack {
                            Text("掃描所選分類")
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
                        .background(selectedCategories.isEmpty || isProcessing ? Color(.systemGray3) : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(selectedCategories.isEmpty || isProcessing)
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
            .onAppear {
                loadScanResultsFromLocal()
                Task { await refreshCategoryCounts() }
            }

        }
    }
    
    // MARK: - Chunk 掃描核心流程
    func startChunkScan(selected: PhotoCategory?) {
        let categories = selected == nil ? PhotoCategory.allCases : [selected!]
        startScanMultiple(selected: categories)
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
    
    func startScanMultiple(selected: [PhotoCategory]) {
        guard !selected.isEmpty else { return }
        isProcessing = true

        Task {
            // 重置所選分類進度
            await MainActor.run {
                selected.forEach { processedCounts[$0] = 0 }
            }

            for cat in selected {
                // 以下流程都和 startChunkScan 裡每個 cat 的內容一樣
                let assets = await fetchAssetsAsync(for: cat)
                var seen = Set<String>()
                let uniqueAssets = assets
                    .filter { seen.insert($0.localIdentifier).inserted }
                    .sorted {
                        ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast)
                    }

                await MainActor.run {
                    categoryCounts[cat] = uniqueAssets.count
                }

                let windowSize = 50
                let chunkSize = 300
                var prevTailEmbs: [[Float]] = []
                var prevTailIds: [String] = []
                let globalIds = uniqueAssets.map { $0.localIdentifier }

                for chunkStart in stride(from: 0, to: uniqueAssets.count, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, uniqueAssets.count)
                    let chunkAssets = Array(uniqueAssets[chunkStart..<chunkEnd])

                    let pairs = await loadImagesWithIds(from: chunkAssets)
                    let chunkIdsFiltered = pairs.map(\.id)
                    let images = pairs.map(\.image)

                    let embs = await batchExtractEmbeddingsChunked(images: images)
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

                    await MainActor.run {
                        processedCounts[cat, default: 0] += chunkAssets.count

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

                        let groups = groupSimilarImages(pairs: globalPairs)
                        scanResults[cat] = ScanResult(
                            date: Date(),
                            duplicateCount: groups.flatMap{$0}.count,
                            lastGroups: groups,
                            assetIds: uniqueAssets.map { $0.localIdentifier }
                        )

                        saveScanResultsToLocal()
                    }

                    if embs.count > windowSize {
                        prevTailEmbs = Array(embs.suffix(windowSize))
                        prevTailIds  = Array(chunkIdsFiltered.suffix(windowSize))
                    } else {
                        prevTailEmbs = embs
                        prevTailIds  = chunkIdsFiltered
                    }
                }
            }

            await MainActor.run { isProcessing = false }
        }
    }
    func loadScanResultsFromLocal() {
        if let data = UserDefaults.standard.data(forKey: scanResultsKey),
           let results = try? JSONDecoder().decode([PhotoCategory: ScanResult].self, from: data) {
            scanResults = results
        }
    }


}




#Preview {
    ContentView()
}


