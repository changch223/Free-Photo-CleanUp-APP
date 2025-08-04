//
//  ContentView.swift
//  Free Photo CleanUp APP
//

import SwiftUI
import Photos

struct PersistedScanSummary: Codable {
    var date: Date
    var duplicateCount: Int
    // 如果需要在「查看」頁快速啟動，僅保存「每組重複的 asset local IDs」，
    // 而不是全量的 assetIds。大幅縮小資料量。
    var duplicateGroupsByAssetIDs: [[String]]? // 可選：若太大，也可不存，點查看時再載
}

struct ResultRowView: View {
    let category: PhotoCategory
    let total: Int
    let processed: Int
    let countsLoading: Bool
    let result: ScanResult?
    let similarPairs: [(Int, Int)]      // <--- 新增
     let images: [UIImage]               // <--- 新增

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                
                if countsLoading && total == 0 {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.9)
                        Text("正在取得總數…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("已掃描 \(processed) / \(total) 張")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if total > 0 {
                        ProgressView(value: Double(processed), total: Double(total))
                            .tint(.blue)
                            .frame(maxWidth: 140)
                            .scaleEffect(x: 1, y: 1.15, anchor: .center)
                            .animation(.easeInOut(duration: 0.4), value: processed)
                    } else {
                        ProgressView()
                            .opacity(0.3)
                            .frame(maxWidth: 140)
                    }
                }
            }
            Spacer()
            if let result, result.duplicateCount > 0 {
                Text("重複 \(result.duplicateCount) 張")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                NavigationLink("查看") {
                    LazyView {
                        SimilarImagesView(
                            similarPairs: similarPairs,
                            images: images
                        )
                    }
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.13))
                .cornerRadius(10)
            } else {
                Text("無重複")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }

        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color(.black).opacity(0.07), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 4)
    }
}


struct LazyView<Content: View>: View {
    let build: () -> Content
    var body: some View { build() }
}

typealias PersistedScanSummaries = [PhotoCategory.RawValue: PersistedScanSummary]

func summariesURL() -> URL {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return dir.appendingPathComponent("scan_results_v2.json")
}


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

extension ContentView {
    // 頁首：主題icon + 標題
    var headerView: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(.blue)
                .padding(.top, 30)
            Text("智慧照片清理")
                .font(.largeTitle).bold()
                .foregroundColor(.primary)
            Text("快速掃描並清除手機內重複的照片，釋放更多寶貴的儲存空間。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // 分類選擇
    var categorySelectionView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("選擇掃描類別")
                .font(.headline)
                .foregroundColor(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(PhotoCategory.allCases, id: \.self) { category in
                        Button(action: {
                            if !isProcessing { // 掃描中不允許點選
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text(category.rawValue)
                                    .fontWeight(.semibold)
                                // 加上進度圈圈
                                if isProcessing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(selectedCategories.contains(category) ? Color.blue : Color(.systemGray5))
                            .foregroundColor(selectedCategories.contains(category) ? .white : .primary)
                            .font(.system(size: 18, weight: .semibold))
                            .shadow(color: selectedCategories.contains(category) ? .blue.opacity(0.15) : .clear, radius: 3, x: 0, y: 2)
                            .cornerRadius(24)
                            .opacity(isProcessing ? 0.6 : 1) // 掃描時半透明
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing) // 掃描時 disable
                        
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.top, 10)
    }
    
    // 按鈕
    var actionButtonsView: some View {
        VStack(spacing: 15) {
            Button(action: {
                startChunkScan(selected: nil)
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("一鍵掃描全部")
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.0)
                            .padding(.leading, 6)
                    }
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isProcessing ? Color.gray : Color.green)
                .cornerRadius(16)
                .shadow(radius: 7, y: 3)
            }
            .disabled(isProcessing)
            // ...同下略...
            
            
            Button(action: {
                startScanMultiple(selected: Array(selectedCategories))
            }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("掃描所選分類")
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.0)
                            .padding(.leading, 6)
                    }
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedCategories.isEmpty || isProcessing ? Color(.systemGray3) : Color.orange)
                .cornerRadius(16)
                .shadow(radius: 7, y: 3)
            }
            .disabled(selectedCategories.isEmpty || isProcessing)
        }
        .padding(.vertical)
    }
    
    var globalProgressView: some View {
        let totalProcessed = processedCounts.values.reduce(0, +)
        let totalCount = photoVM.categoryCounts.values.reduce(0, +)
        return Group {
            if isProcessing && totalCount > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: Double(totalProcessed), total: Double(max(totalCount, 1)))
                        .accentColor(.blue)
                    Text("總進度 \(totalProcessed) / \(totalCount) 張")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal)
            }
        }
    }
    
    // 掃描結果
    var scanResultsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("掃描結果")
                .font(.headline)
                .padding(.leading, 4)
            ForEach(PhotoCategory.allCases, id: \.self) { category in
                let result = scanResults[category]
                let pairs = result != nil ? pairsFromGroups(result!.lastGroups) : []
                let images = result != nil ? loadImagesForCategory(category, scanResults: scanResults) : []
                ResultRowView(
                    category: category,
                    total: photoVM.categoryCounts[category] ?? 0,
                    processed: processedCounts[category] ?? 0,
                    countsLoading: photoVM.countsLoading,
                    result: result,
                    similarPairs: pairs,
                    images: images
                )
            }
        }
        .padding(.top)
    }
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
    @State private var showFinishAlert = false
    @State private var totalDuplicatesFound = 0
    @State private var countsLoading = true   // 是否仍在計算各分類總數
    @StateObject private var photoVM = PhotoLibraryViewModel()

    
    // --- 本地快取 key
    let scanResultsKey = "ScanResults"
    
    var body: some View {
           NavigationView {
               VStack(spacing: 0) {
                   headerView
                   categorySelectionView
                   actionButtonsView
                   globalProgressView
                   scanResultsView
                   Spacer()
               }
               .padding(.top, 4)
               .padding(.horizontal)
               .background(Color(.systemGray6))
               .navigationBarHidden(true)
               .alert(isPresented: $showFinishAlert) {
                   Alert(
                       title: Text("掃描完成"),
                       message: Text("共找到 \(totalDuplicatesFound) 張重複照片"),
                       dismissButton: .default(Text("確定"))
                   )
               }
               .onAppear {
                   Task {
                       let summaries = await loadScanSummariesFromDisk()
                       // 把輕量資料轉成畫面用的狀態（只需要 duplicateCount 即可）
                       for (raw, s) in summaries {
                           if let cat = PhotoCategory(rawValue: raw) {
                               self.scanResults[cat] = ScanResult(
                                date: s.date,
                                duplicateCount: s.duplicateCount,
                                lastGroups: [],          // 不在啟動時帶回
                                assetIds: []             // 不在啟動時帶回
                               )
                           }
                       }
                   }
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
    func loadImagesWithIds(from assets: [PHAsset], maxConcurrent: Int = 8) async -> [(id: String, image: UIImage)] {
        let manager = PHCachingImageManager.default() // 可重用快取管理
        let req = PHImageRequestOptions()
        req.isSynchronous = false
        req.deliveryMode  = .fastFormat         // 快速、小記憶體
        req.resizeMode    = .fast
        req.isNetworkAccessAllowed = false

        let target = CGSize(width: 224, height: 224)

        var pairs = Array<(String, UIImage?)>(repeating: ("", nil), count: assets.count)

        // 以固定併發度分批
        var i = 0
        while i < assets.count {
            let upper = min(i + maxConcurrent, assets.count)
            await withTaskGroup(of: Void.self) { group in
                for idx in i..<upper {
                    let asset = assets[idx]
                    let id = asset.localIdentifier
                    group.addTask {
                        await withCheckedContinuation { cont in
                            manager.requestImage(for: asset,
                                                 targetSize: target,
                                                 contentMode: .aspectFill, // 小縮圖更快
                                                 options: req) { img, _ in
                                pairs[idx] = (id, img)
                                cont.resume()
                            }
                        }
                    }
                }
                await group.waitForAll()
            }
            i = upper
            autoreleasepool { } // 幫助釋放暫存
        }

        return pairs.compactMap { (id, img) in
            guard let img else { return nil }
            return (id, img)
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
    
    
    func startScanMultiple(selected: [PhotoCategory]) {
        guard !selected.isEmpty else { return }
        isProcessing = true

        Task {
            // 重置所選分類進度
            await MainActor.run {
                selected.forEach { processedCounts[$0] = 0 }
            }

            for cat in selected {
                let assets = await fetchAssetsAsync(for: cat)
                var seen = Set<String>()
                let uniqueAssets = assets
                    .filter { seen.insert($0.localIdentifier).inserted }
                    .sorted { ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) }

                await MainActor.run {
                    photoVM.categoryCounts[cat] = uniqueAssets.count
                }

                let windowSize = 50
                let chunkSize = 250
                var prevTailEmbs: [[Float]] = []
                var prevTailIds: [String] = []
                let globalIds = uniqueAssets.map { $0.localIdentifier }

                var allGroups: [[Int]] = []
                var allAssetIds: [String] = []

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

                    // 只要一份 globalPairs + groups
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
                    allGroups += groups
                    allAssetIds += chunkIdsFiltered

                    // --- 重點：每個 chunk 結束就即時刷新 ---
                    await MainActor.run {
                        scanResults[cat] = ScanResult(
                            date: Date(),
                            duplicateCount: allGroups.flatMap{$0}.count,
                            lastGroups: allGroups,
                            assetIds: allAssetIds
                        )
                        processedCounts[cat, default: 0] += chunkAssets.count
                    }

                    // 尾部保留
                    if embs.count > windowSize {
                        prevTailEmbs = Array(embs.suffix(windowSize))
                        prevTailIds  = Array(chunkIdsFiltered.suffix(windowSize))
                    } else {
                        prevTailEmbs = embs
                        prevTailIds  = chunkIdsFiltered
                    }
                }

                // 結束時存到本地
                await MainActor.run {
                    scanResults[cat] = ScanResult(
                        date: Date(),
                        duplicateCount: allGroups.flatMap{$0}.count,
                        lastGroups: allGroups,
                        assetIds: allAssetIds
                    )
                    saveScanResultsToLocal()
                }
            }

            await MainActor.run {
                isProcessing = false
                // 統計所有分類重複
                totalDuplicatesFound = scanResults.values.map { $0.duplicateCount }.reduce(0, +)
                showFinishAlert = true
            }
        }
    }

    
    func loadScanResultsFromLocal() {
        if let data = UserDefaults.standard.data(forKey: scanResultsKey),
           let results = try? JSONDecoder().decode([PhotoCategory: ScanResult].self, from: data) {
            scanResults = results
        }
    }
    
    func saveScanSummariesToDisk(_ summaries: PersistedScanSummaries) {
        Task.detached(priority: .background) {
            do {
                let data = try JSONEncoder().encode(summaries)
                try data.write(to: summariesURL(), options: .atomic)
            } catch {
                print("saveScanSummariesToDisk error:", error)
            }
        }
    }
    
    @MainActor
    func loadScanSummariesFromDisk() async -> PersistedScanSummaries {
        await withCheckedContinuation { cont in
            Task.detached(priority: .background) {
                do {
                    let url = summariesURL()
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        cont.resume(returning: [:])
                        return
                    }
                    let data = try Data(contentsOf: url)
                    let decoded = try JSONDecoder().decode(PersistedScanSummaries.self, from: data)
                    cont.resume(returning: decoded)
                } catch {
                    print("loadScanSummariesFromDisk error:", error)
                    cont.resume(returning: [:])
                }
            }
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


func loadImagesForCategory(_ cat: PhotoCategory, scanResults: [PhotoCategory: ScanResult]) -> [UIImage] {
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

#Preview {
    ContentView()
}


