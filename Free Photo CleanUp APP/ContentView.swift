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
    case video = "影片"
    case screenRecording = "螢幕錄影"
    var id: String { rawValue }
}

struct ScanResult: Codable {
    var date: Date
    var duplicateCount: Int
    var lastGroups: [[Int]]
}

struct CategorySummary: Identifiable {
    var id: PhotoCategory { category }
    var category: PhotoCategory
    var name: String { category.rawValue }
    var count: Int
    var duplicateCount: Int
}

struct ContentView: View {
    // 狀態
    @State private var categoryCounts: [PhotoCategory: Int] = [:]
    @State private var scanResults: [PhotoCategory: ScanResult] = [:]
    @State private var selectedCategories: Set<PhotoCategory> = []
    @State private var lastCleanupSpace: Double = 0.0
    @State private var selectedCategory: PhotoCategory? = nil
    @State private var isProcessing = false
    @State private var processingIndex = 0
    @State private var processingTotal = 0
    @State private var scanningCategory: PhotoCategory? = nil

    var summaries: [CategorySummary] {
        PhotoCategory.allCases.map { cat in
            let dupCount = scanResults[cat]?.duplicateCount ?? 0
            return CategorySummary(category: cat, count: categoryCounts[cat] ?? 0, duplicateCount: dupCount)
        }
    }
    
    // 本地快取 key
    let scanResultsKey = "ScanResults"
    let lastCleanupSpaceKey = "LastCleanupSpace"

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
                        Button(action: { scanAllCategories() }) {
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
                                ForEach(summaries) { cat in
                                    Button(action: {
                                        if selectedCategories.contains(cat.category) {
                                            selectedCategories.remove(cat.category)
                                        } else {
                                            selectedCategories.insert(cat.category)
                                        }
                                    }) {
                                        VStack(spacing: 2) {
                                            Text(cat.name)
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(selectedCategories.contains(cat.category) ? Color.orange : Color(.systemGray5))
                                                .foregroundColor(selectedCategories.contains(cat.category) ? .white : .primary)
                                                .cornerRadius(20)
                                            Text("\(cat.count) 張")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal)

                        Button(action: {
                            startScanMultiple(selected: Array(selectedCategories))
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


                        VStack(spacing: 10) {
                            ForEach(summaries) { cat in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(cat.name)
                                        Text("共 \(cat.count) 張").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let res = scanResults[cat.id], res.duplicateCount > 0 {
                                        Text("重複 \(res.duplicateCount) 張")
                                            .foregroundColor(.red).font(.caption)
                                        NavigationLink("查看重複") {
                                            let pairs = pairsFromGroups(res.lastGroups)
                                            let imgs = loadImagesForCategory(cat.id)
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

                        if isProcessing {
                            VStack {
                                Text("掃描中 \(processingIndex)/\(processingTotal)")
                                ProgressView(value: Double(processingIndex), total: Double(processingTotal))
                            }.padding()
                        }

                        Spacer()
                    }
                }
                .background(Color(.systemGroupedBackground))
                .onAppear { Task { await refreshCategoryCounts() } }
            }
        }

        // MARK: - 掃描邏輯
        func scanAllCategories() {
            isProcessing = true
            processingTotal = PhotoCategory.allCases.count
            processingIndex = 0

            Task {
                for cat in PhotoCategory.allCases {
                    let result = await scanCategory(cat)
                    scanResults[cat] = result
                    processingIndex += 1
                }
                isProcessing = false
                saveScanResultsToLocal()
            }
        }

        func scanSelectedCategories(_ selected: [PhotoCategory]) {
            isProcessing = true
            processingTotal = selected.count
            processingIndex = 0

            Task {
                for cat in selected {
                    let result = await scanCategory(cat)
                    scanResults[cat] = result
                    processingIndex += 1
                }
                isProcessing = false
                saveScanResultsToLocal()
            }
        }

        func scanCategory(_ cat: PhotoCategory) async -> ScanResult {
            let assets = await Free_Photo_CleanUp_APP.fetchAssets(for: cat)
            let images = await loadImages(from: assets)
            let embeddings = await batchExtractEmbeddings(images: images)
            let pairs = findSimilarPairs(embeddings: embeddings, threshold: 0.97, window: 50)
            let groups = groupSimilarImages(pairs: pairs)
            let dupCount = groups.flatMap{$0}.count
            return ScanResult(date: Date(), duplicateCount: dupCount, lastGroups: groups)
        }

        // --- 分類張數
        func refreshCategoryCounts() async {
            for cat in PhotoCategory.allCases {
                let assets = await Free_Photo_CleanUp_APP.fetchAssets(for: cat)
                await MainActor.run { categoryCounts[cat] = assets.count }
            }
        }

        // --- 儲存/讀取本地 UserDefaults
        func saveScanResultsToLocal() {
            if let data = try? JSONEncoder().encode(scanResults) {
                UserDefaults.standard.set(data, forKey: "ScanResults")
            }
        }
        func loadScanResultsFromLocal() {
            if let data = UserDefaults.standard.data(forKey: "ScanResults"),
               let dict = try? JSONDecoder().decode([PhotoCategory: ScanResult].self, from: data) {
                scanResults = dict
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
    
    // MARK: - 扫描核心流程
    func startScan(selected: PhotoCategory?) {
        let categories: [PhotoCategory] = selected == nil ? PhotoCategory.allCases : [selected!]
        isProcessing = true
        processingTotal = categories.map { categoryCounts[$0] ?? 0 }.reduce(0, +)
        processingIndex = 0

        Task {
            for cat in categories {
                // 1. 取 assets
                let assets = await fetchAssetsAsync(for: cat)
                // 2. 取 images
                let images = await loadImages(from: assets)
                // 3. 存 images 到本地
                saveImagesToDisk(images, for: cat)
                // 4. 計算 embedding
                let embeddings = await batchExtractEmbeddings(images: images)
                // 5. 找相似 pairs、分組
                let pairs = findSimilarPairs(embeddings: embeddings, threshold: 0.97, window: 50)
                let groups = groupSimilarImages(pairs: pairs)
                let dupCount = groups.flatMap{$0}.count
                // 6. 儲存掃描結果
                scanResults[cat] = ScanResult(date: Date(), duplicateCount: dupCount, lastGroups: groups)

                processingIndex += images.count // 或 +1 依你需要
            }
            isProcessing = false
            saveScanResultsToLocal()
        }
    }
    
    // 你可以包裝原本 fetchAssets(for:completion:) 成 async 版本
    func fetchAssetsAsync(for category: PhotoCategory) async -> [PHAsset] {
        await withCheckedContinuation { continuation in
            fetchAssets(for: category) { assets in
                continuation.resume(returning: assets)
            }
        }
    }
    
    
    func startScanMultiple(selected: [PhotoCategory]) {
        isProcessing = true
        processingTotal = selected.count
        processingIndex = 0
        Task {
            for cat in selected {
                await startScanOneCategory(cat)
                processingIndex += 1
            }
            isProcessing = false
            saveScanResultsToLocal()
        }
    }

    // 把一個分類的掃描邏輯包成 async function
    func startScanOneCategory(_ cat: PhotoCategory) async {
        let assets = await fetchAssetsAsync(for: cat)
        let images = await loadImages(from: assets)
        saveImagesToDisk(images, for: cat)
        let embeddings = await batchExtractEmbeddings(images: images)
        let pairs = findSimilarPairs(embeddings: embeddings, threshold: 0.97, window: 50)
        let groups = groupSimilarImages(pairs: pairs)
        let dupCount = groups.flatMap{$0}.count
        await MainActor.run {
            scanResults[cat] = ScanResult(date: Date(), duplicateCount: dupCount, lastGroups: groups)
        }
    }

    
   
    func loadImagesForCategory(_ cat: PhotoCategory) -> [UIImage] {
        return loadImagesFromDisk(for: cat)
    }

    
    // ---- 原有照片數量統計保留 ----
    func loadAllCategoryCounts() {
        for category in PhotoCategory.allCases {
            fetchAssets(for: category) { assets in
                DispatchQueue.main.async {
                    categoryCounts[category] = assets.count
                }
            }
        }
    }
    
    func loadImages(from assets: [PHAsset]) async -> [UIImage] {
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
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                continuation.resume(returning: loadedImages)
            }
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
        case .screenRecording:
            options.predicate = NSPredicate(format: "mediaSubtypes & %d != 0", 524288)
            let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
            var arr: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in arr.append(asset) }
            completion(arr)
        case .video:
            let allVideos = PHAsset.fetchAssets(with: .video, options: options)
            var arr: [PHAsset] = []
            allVideos.enumerateObjects { asset, _, _ in
                if asset.mediaSubtypes.rawValue & 524288 == 0 {
                    arr.append(asset)
                }
            }
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
}

#Preview {
    ContentView()
}
