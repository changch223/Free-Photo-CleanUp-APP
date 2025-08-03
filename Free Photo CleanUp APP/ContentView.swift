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

    // 本地快取 key
    let scanResultsKey = "ScanResults"
    let lastCleanupSpaceKey = "LastCleanupSpace"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Free Photo CleanUp")
                        .font(.largeTitle).fontWeight(.bold)
                        .padding(.top, 24)
                    Text("幫你找出手機裡的重複照片，一鍵清理釋放空間")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.bottom, 10)
                    
                    // 主掃描按鈕
                    Button(action: { startScan(selected: nil) }) {
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
                    
                    // 分類多選，顯示數量
                    VStack(alignment: .leading, spacing: 8) {
                        Text("選擇要掃描的分類（可多選）")
                            .font(.subheadline).foregroundColor(.secondary)
                        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3), spacing: 14) {
                            ForEach(PhotoCategory.allCases) { cat in
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
                                        Text("\(categoryCounts[cat, default: 0]) 張")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // 多分類掃描主按鈕
                    Button(action: {
                        if !selectedCategories.isEmpty {
                            startScanMultiple(selected: Array(selectedCategories))
                        }
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
                    .padding(.bottom, 8)
                    
                    // 分類摘要列表
                    VStack(spacing: 10) {
                        ForEach(PhotoCategory.allCases) { cat in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(cat.rawValue).font(.body)
                                    Text("共 \(categoryCounts[cat, default: 0]) 張").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let res = scanResults[cat], res.duplicateCount > 0 {
                                    Text("重複 \(res.duplicateCount) 張")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    NavigationLink("查看重複") {
                                        // 用 pairsFromGroups + loadImagesForCategory 實作即可
                                        SimilarImagesView(
                                            similarPairs: pairsFromGroups(res.lastGroups),
                                            images: loadImagesForCategory(cat)
                                        )
                                    }
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                                } else if let _ = scanResults[cat] {
                                    Text("無重複")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                } else {
                                    Text("尚未掃描")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                    .padding(.top, 8)
                    
                    // 掃描進度條
                    if isProcessing {
                        VStack(spacing: 10) {
                            Text("正在掃描 \(scanningCategory?.rawValue ?? "全部") \(processingIndex)/\(processingTotal)")
                            ProgressView(value: Double(processingIndex), total: Double(processingTotal))
                        }
                        .padding()
                    }
                    
                    Spacer()
                }
            }
            .onAppear { loadAllCategoryCounts(); loadScanResultsFromLocal() }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    // MARK: - 扫描核心流程 (僅保留呼叫結構, 需串接你的embedding判重)
    func startScan(selected: PhotoCategory?) {
        scanningCategory = selected
        isProcessing = true
        processingIndex = 0
        // 根據 selected 分類取得 assets
        let categories: [PhotoCategory] = selected == nil ? PhotoCategory.allCases : [selected!]
        processingTotal = categories.map { categoryCounts[$0] ?? 0 }.reduce(0, +)
        
        // 建議：根據分類、逐步分析（Demo只模擬結果）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for cat in categories {
                // 你這裡實際應該是照片分析&分組，這邊只做demo
                let demoRes = ScanResult(date: Date(), duplicateCount: Int.random(in: 2...12), lastGroups: [[1,2,3],[10,11]])
                scanResults[cat] = demoRes
            }
            saveScanResultsToLocal()
            isProcessing = false
        }
    }
    
    func startScanMultiple(selected: [PhotoCategory]) {
         for cat in selected {
             startScan(selected: cat)
         }
     }
    
    // MARK: - 本地存取
    func saveScanResultsToLocal() {
        if let data = try? JSONEncoder().encode(scanResults) {
            UserDefaults.standard.set(data, forKey: scanResultsKey)
        }
        UserDefaults.standard.set(lastCleanupSpace, forKey: lastCleanupSpaceKey)
    }
    func loadScanResultsFromLocal() {
        if let data = UserDefaults.standard.data(forKey: scanResultsKey),
           let dict = try? JSONDecoder().decode([PhotoCategory: ScanResult].self, from: data) {
            scanResults = dict
        }
        lastCleanupSpace = UserDefaults.standard.double(forKey: lastCleanupSpaceKey)
    }

    // 根據 lastGroups 產生 pairs 給 SimilarImagesView
    func pairsFromGroups(_ groups: [[Int]]) -> [(Int,Int)] {
        var pairs: [(Int,Int)] = []
        for g in groups {
            for i in 0..<(g.count-1) {
                pairs.append((g[i], g[i+1]))
            }
        }
        return pairs
    }
    // [須實作] 取得該分類所有 UIImage（你可用你的 loadImages 實現）
    func loadImagesForCategory(_ cat: PhotoCategory) -> [UIImage] {
        // TODO: 拿這個分類對應的所有 UIImage
        return []
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
