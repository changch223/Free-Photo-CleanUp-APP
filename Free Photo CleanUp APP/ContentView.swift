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

struct ResultRowView: View, Equatable {
    let category: PhotoCategory
    let total: Int
    let processed: Int
    let countsLoading: Bool
    let result: ScanResult?
    let similarPairs: [(Int, Int)]

    static func == (lhs: ResultRowView, rhs: ResultRowView) -> Bool {
        // 只比對這些即可
        lhs.category == rhs.category &&
        lhs.total == rhs.total &&
        lhs.processed == rhs.processed &&
        lhs.result?.duplicateCount == rhs.result?.duplicateCount
    }

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
                    SimilarImagesView(
                        similarPairs: similarPairs,
                        assetIds: result.assetIds
                    )
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
        VStack(alignment: .leading, spacing: 12) {
            Text("選擇掃描類別")
                .font(.headline)
            Text("最多只能選擇1000張照片")
                .font(.subheadline)
            ForEach(PhotoCategory.allCases, id: \.self) { category in
                let chunks = categoryAssetChunks[category] ?? []
                let chunkCountAll = chunks.count
                let selectedIdx = selectedChunkIndex(for: category)
                let displayCount = chunkCount(for: category, idx: selectedIdx)

                HStack(spacing: 10) {
                    // 勾選框
                    Button {
                        if !isProcessing {
                            var newSelection = selectedCategories
                            if newSelection.contains(category) {
                                newSelection.remove(category)
                            } else {
                                newSelection.insert(category)
                            }
                            // 計算總合是否超過 1000
                            let total = newSelection.reduce(0) { acc, cat in
                                chunkCount(for: cat, idx: selectedChunkIndex(for: cat)) + acc
                            }
                            if total > 1000 {
                                overLimitMessage = "已選總數 \(total) 張，超過 1000 上限。請減少分類或組合。"
                                showOverLimitAlert = true
                            } else {
                                selectedCategories = newSelection
                            }
                        }
                    } label: {
                        Image(systemName: selectedCategories.contains(category) ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundColor(selectedCategories.contains(category) ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    // 分類名稱 + 該組張數
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                        Text("第 \(selectedIdx + 1) 組 · \(displayCount) 張")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    // 分組下拉（有多組才顯示）
                    if chunkCountAll > 1 {
                        Menu {
                            ForEach(0..<chunkCountAll, id: \.self) { i in
                                Button {
                                    selectedCategoryChunks[category] = i
                                    // 如果已勾選，改變組時也要重新檢查合計數
                                    if selectedCategories.contains(category) {
                                        let total = selectedCategories.reduce(0) { acc, cat in
                                            chunkCount(for: cat, idx: selectedCategoryChunks[cat] ?? 0) + acc
                                        }
                                        if total > 1000 {
                                            overLimitMessage = "已選總數 \(total) 張，超過 1000 上限。請減少分類或組合。"
                                            showOverLimitAlert = true
                                            // 自動取消這個分類
                                            selectedCategories.remove(category)
                                        }
                                    }
                                } label: {
                                    Text("第 \(i+1) 組（\(chunks[i].count) 張）")
                                }
                            }
                        } label: {
                            HStack() {
                                Text("第 \(selectedIdx + 1) 組")
                                Image(systemName: "chevron.down")
                            }
                            .padding(.horizontal, 10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .disabled(isProcessing)
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .opacity(isProcessing ? 0.6 : 1)
            }
        }
        .padding(.top, 10)
        .alert(isPresented: $showOverLimitAlert) {
            Alert(title: Text("超過限制"), message: Text(overLimitMessage), dismissButton: .default(Text("確定")))
        }
    }





    
    // 按鈕
    var actionButtonsView: some View {
        VStack(spacing: 15) {
            
    
            
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
        // 每個選取分類取目前所選 chunk 的數量
        let selectedTotal = selectedCategories.reduce(0) { acc, cat in
            let idx = selectedCategoryChunks[cat] ?? 0
            let count = categoryAssetChunks[cat]?[safe: idx]?.count ?? 0
            return acc + count
        }
        let selectedProcessed = selectedCategories.reduce(0) { $0 + (processedCounts[$1] ?? 0) }
        return Group {
            if isProcessing && selectedTotal > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: Double(selectedProcessed), total: Double(max(selectedTotal, 1)))
                        .accentColor(.blue)
                    Text("總進度 \(selectedProcessed) / \(selectedTotal) 張")
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
                ResultRowView(
                    category: category,
                    total: photoVM.categoryCounts[category] ?? 0,
                    processed: processedCounts[category] ?? 0,
                    countsLoading: photoVM.countsLoading,
                    result: result,
                    similarPairs: pairs
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
    @State private var isProcessing = false
    @State private var processingIndex = 0
    @State private var processingTotal = 0
    @State private var showFinishAlert = false
    @State private var totalDuplicatesFound = 0
    @State private var countsLoading = true   // 是否仍在計算各分類總數
    @StateObject private var photoVM = PhotoLibraryViewModel()
    @State private var selectedCategories: Set<PhotoCategory> = []
   
    // MARK: - Selection states & alerts
    @State private var showOverLimitAlert = false
    @State private var overLimitMessage = ""

    // 你已有：分類→分組（每組<=1000）
    @State private var categoryAssetChunks: [PhotoCategory: [[PHAsset]]] = [:]
    // 你已有：分類→目前選到第幾組（>1000 時才有意義）
    @State private var selectedCategoryChunks: [PhotoCategory: Int] = [:]

    // MARK: - Helper: 背景同步載圖，保證只回呼一次
    func requestImageSync(_ asset: PHAsset,
                          target: CGSize,
                          mode: PHImageContentMode = .aspectFill) -> UIImage? {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true            // 只回呼一次
        opts.deliveryMode = .fastFormat
        opts.resizeMode   = .fast
        opts.isNetworkAccessAllowed = false

        var out: UIImage?
        PHImageManager.default().requestImage(for: asset,
                                              targetSize: target,
                                              contentMode: mode,
                                              options: opts) { img, _ in
            out = img
        }
        return out
    }

    
    // MARK: - Helpers
    private func isOverLimitCategory(_ category: PhotoCategory) -> Bool {
        (categoryAssetChunks[category]?.count ?? 0) > 1
    }

    private func selectedChunkIndex(for category: PhotoCategory) -> Int {
        selectedCategoryChunks[category] ?? 0
    }

    private func chunkCount(for category: PhotoCategory, idx: Int) -> Int {
        categoryAssetChunks[category]?[safe: idx]?.count ?? 0
    }

    private func totalCount(for category: PhotoCategory) -> Int {
        (categoryAssetChunks[category]?.flatMap { $0 }.count) ?? 0
    }

    /// 回傳「此分類在目前選擇下」會掃描的張數
    private func countForCategoryInSelection(_ category: PhotoCategory) -> Int {
        if isOverLimitCategory(category) {
            return chunkCount(for: category, idx: selectedChunkIndex(for: category))
        } else {
            return totalCount(for: category)
        }
    }

    /// 計算一組選擇的合計張數（多選時用）
    private func totalCountOfSelection(_ selection: Set<PhotoCategory>) -> Int {
        selection.reduce(0) { $0 + countForCategoryInSelection($1) }
    }

    /// 嘗試切換某分類的勾選（包含規則與警告）
    private func tryToggle(_ category: PhotoCategory) {
        // 取消勾選
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
            return
        }
        // 要勾選
        let targetIsOver = isOverLimitCategory(category)

        // 若目標分類超過 1000：只能單選（自動清掉其他）
        if targetIsOver {
            // 若已經選了別的分類，提示並不切換（或自動改為只選這個；這裡採提示較清楚）
            if !selectedCategories.isEmpty {
                overLimitMessage = "\(category.rawValue) 共有 \(totalCount(for: category)) 張，已超過 1000，**只能單選**。請先取消其它分類後再選擇。"
                showOverLimitAlert = true
                return
            }
            // 設定目前組（若還沒設過）
            if selectedCategoryChunks[category] == nil { selectedCategoryChunks[category] = 0 }
            selectedCategories = [category]
            return
        }

        // 目標 ≤ 1000：可多選，但若目前已有「超過1000的分類」就不行
        if let over = selectedCategories.first(where: { isOverLimitCategory($0) }) {
            overLimitMessage = "\(over.rawValue) 超過 1000 張，已限制單選。請先取消 \(over.rawValue) 後才能多選其他分類。"
            showOverLimitAlert = true
            return
        }

        // 檢查總合是否超過 1000
        var newSel = selectedCategories
        newSel.insert(category)
        let total = totalCountOfSelection(newSel)
        if total > 1000 {
            overLimitMessage = "你選了 \(total) 張，超過 1000 上限。請減少分類或改成只選一個大分類的其中一組。"
            showOverLimitAlert = true
            return
        }
        selectedCategories = newSel
    }

    /// 當 >1000 類別更換組別：強制改成只選該類別
    private func didChangeChunk(for category: PhotoCategory, to newIndex: Int) {
        selectedCategoryChunks[category] = newIndex
        // 規則：>1000 必須單選
        selectedCategories = [category]
    }



    
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
                       
                       // 載入分組
                       for cat in PhotoCategory.allCases {
                           let assets = await fetchAssetsAsync(for: cat)
                           let chunks = splitAssetsByThousand(assets)       // 你已有的切組方法
                           categoryAssetChunks[cat] = chunks
                           if chunks.count > 1 {
                               selectedCategoryChunks[cat] = 0             // 預設第一組
                           }
                       }
                   }
               }
           }
    }

    func totalSelectedAssetsCount() -> Int {
        selectedCategories.reduce(0) { acc, cat in
            let chunks = categoryAssetChunks[cat] ?? []
            let idx = (chunks.count > 1) ? (selectedCategoryChunks[cat] ?? 0) : 0
            return acc + (chunks[safe: idx]?.count ?? 0)
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
        let target = CGSize(width: 224, height: 224)
        var pairs = Array<(String, UIImage?)>(repeating: ("", nil), count: assets.count)
        var i = 0
        while i < assets.count {
            let upper = min(i + maxConcurrent, assets.count)
            await withTaskGroup(of: Void.self) { group in
                for idx in i..<upper {
                    let asset = assets[idx]
                    let id = asset.localIdentifier
                    group.addTask {
                        let img = await requestImageSync(asset, target: target, mode: .aspectFill)
                        pairs[idx] = (id, img)
                    }
                }
                await group.waitForAll()
            }
            i = upper
            autoreleasepool { }
        }
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
            await MainActor.run {
                selected.forEach { processedCounts[$0] = 0 }
            }

            var sessionDuplicatesFound = 0 // <--- 新增：本次找到的總重複數
            
            for cat in selected {
                // 決定要掃描哪一組 chunk
                let chunks = categoryAssetChunks[cat] ?? []
                let chunkIdx = (chunks.count > 1) ? (selectedCategoryChunks[cat] ?? 0) : 0
                let chunkAssets = chunks[safe: chunkIdx] ?? []
                if chunkAssets.isEmpty { continue }

                var seen = Set<String>()
                let uniqueAssets = chunkAssets
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
                    let chunkSubAssets = Array(uniqueAssets[chunkStart..<chunkEnd])

                    let pairs = await loadImagesWithIds(from: chunkSubAssets)
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

                    // --- 每個 chunk 即時刷新 ---
                    await MainActor.run {
                        scanResults[cat] = ScanResult(
                            date: Date(),
                            duplicateCount: allGroups.flatMap{$0}.count,
                            lastGroups: allGroups,
                            assetIds: allAssetIds
                        )
                        processedCounts[cat, default: 0] += chunkSubAssets.count
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
                    // <--- 這次的重複張數，加進 sessionDuplicatesFound
                    sessionDuplicatesFound += allGroups.flatMap{$0}.count
                }
            }

            await MainActor.run {
                isProcessing = false
                // totalDuplicatesFound = scanResults.values.map { $0.duplicateCount }.reduce(0, +) // 舊
                totalDuplicatesFound = sessionDuplicatesFound // <--- 新：只顯示這次掃描到的
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

/// 傳回：["Selfie": [[id1, id2, ...], [id1001, id1002, ...]], ...]
func splitAssetsByThousand(_ assets: [PHAsset]) -> [[PHAsset]] {
    let chunkSize = 1000
    var result: [[PHAsset]] = []
    var i = 0
    while i < assets.count {
        let end = min(i + chunkSize, assets.count)
        result.append(Array(assets[i..<end]))
        i = end
    }
    return result
}



#Preview {
    ContentView()
}



