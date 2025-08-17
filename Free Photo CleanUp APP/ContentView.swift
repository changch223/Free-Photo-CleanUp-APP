//
//  ContentView.swift
//  Free Photo CleanUp APP
//

import SwiftUI
import Photos
import UIKit
import Accelerate // vImage / vDSP
import CoreImage   // ← 新增
import StoreKit

private var isFirstAppear = true          // 第一次進入頁面
private var reviewAskCounter = 0          // 可簡單節流（可選）
private let kLastReviewPromptDateKey = "LastReviewPromptDateKey"

// 是否距離上次詢問已超過指定天數（預設 180 天）
private func canAskForReviewAgain(minDays: Int = 180) -> Bool {
    let defaults = UserDefaults.standard
    guard let last = defaults.object(forKey: kLastReviewPromptDateKey) as? Date else {
        return true // 從未問過 => 可以問
    }
    let now = Date()
    let days = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
    return days >= minDays
}

// 實際觸發評分，並記錄時間（即使系統不一定會顯示，也先記錄避免頻繁觸發）
private func requestAppReviewIfAppropriate() {
    guard canAskForReviewAgain(minDays: 180) else { return }
    if let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
        SKStoreReviewController.requestReview(in: scene)
        UserDefaults.standard.set(Date(), forKey: kLastReviewPromptDateKey)
    }
}




// 可重用的 CIContext（關掉 color space 以避免額外轉換）
private let sharedCIContext: CIContext = {
    let opts: [CIContextOption: Any] = [
        .workingColorSpace: NSNull(),
        .outputColorSpace:  NSNull()
    ]
    return CIContext(options: opts)
}()

/// 更穩定的模糊判斷：自適應邊緣門檻 + 中心加權 + 變異數雙條件
private func isBlurryAdaptiveCenterWeighted(
    _ image: UIImage,
    varianceThreshold: Float = BLUR_VARIANCE_THRESHOLD, // 例如 60~90
    kStd: Float = 1.0,        // 邊緣門檻 = mean + k*std，建議 0.8~1.5
    minSharpRatioGlobal: Float = 0.12, // 整張最低銳利比例
    minSharpRatioCenter: Float = 0.25, // 中心區域最低銳利比例（更寬鬆）
    gaussianRadius: CGFloat = 0.8      // 降噪
) -> Bool {
    guard let srcCG = image.cgImage else { return false }

    // 1) 前處理（縮放、灰階、輕微降噪）
    let targetW: CGFloat = 224
    let ciIn = CIImage(cgImage: srcCG)
    let sx = targetW / CGFloat(srcCG.width)
    let sy = targetW / CGFloat(srcCG.height)
    let scaled = ciIn.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    let gray = scaled.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    let blurred = gray.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: gaussianRadius])

    // 2) Laplacian 卷積
    let weights: [CGFloat] = [-1,-1,-1, -1,8,-1, -1,-1,-1]
    guard
        let convolved = CIFilter(
            name: "CIConvolution3X3",
            parameters: [
                kCIInputImageKey: blurred,
                "inputWeights": CIVector(values: weights, count: 9),
                "inputBias": 0
            ]
        )?.outputImage
    else { return false }

    // 3) 拉回 RGBA8 buffer（R=G=B）
    let rect = CGRect(x: 0, y: 0,
                      width: Int(max(1, round(targetW))),
                      height: Int(max(1, round(targetW))))
    guard let outCG = sharedCIContext.createCGImage(convolved, from: rect) else { return false }

    let width = outCG.width, height = outCG.height
    let bytesPerPixel = 4, bytesPerRow = width * bytesPerPixel
    var buf = [UInt8](repeating: 0, count: Int(bytesPerRow * height))
    guard let ctx = CGContext(
        data: &buf, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }
    ctx.draw(outCG, in: CGRect(x: 0, y: 0, width: width, height: height))

    // 4) 取 R 通道 -> Float 陣列
    let count = width * height
    var lap = [Float](repeating: 0, count: count)
    var idx = 0
    for i in stride(from: 0, to: buf.count, by: 4) { lap[idx] = Float(buf[i]); idx += 1 }

    // 5) 變異數（整體清晰度指標）
    var mean: Float = 0, meanSquares: Float = 0
    vDSP_meanv(lap, 1, &mean, vDSP_Length(count))
    vDSP_measqv(lap, 1, &meanSquares, vDSP_Length(count))
    let variance = max(0, meanSquares - mean * mean)

    // 6) 自適應邊緣門檻：thr = mean + k*std
    var std: Float = 0
    vDSP_normalize(lap, 1, nil, 1, &mean, &std, vDSP_Length(count)) // 只取出 mean/std
    let edgeThr = mean + kStd * std

    // 7) 全圖銳利比例
    let sharpGlobal = lap.reduce(into: 0) { $0 += ($1 > edgeThr ? 1 : 0) }
    let sharpRatioGlobal = Float(sharpGlobal) / Float(max(1, count))

    // 8) 中心 60% 區域銳利比例（主體保護）
    let cx0 = Int(Float(width) * 0.2),  cx1 = Int(Float(width) * 0.8)
    let cy0 = Int(Float(height) * 0.2), cy1 = Int(Float(height) * 0.8)
    var centerSharp = 0, centerTotal = 0
    for y in cy0..<cy1 {
        let row = y * width
        for x in cx0..<cx1 {
            if lap[row + x] > edgeThr { centerSharp += 1 }
            centerTotal += 1
        }
    }
    let sharpRatioCenter = Float(centerSharp) / Float(max(1, centerTotal))

    // 9) 決策：需同時「變異數低」且「中心與全圖銳利比例都低」才判定模糊
    let looksBlurryByVar   = variance < varianceThreshold
    let looksSharpGlobally = sharpRatioGlobal >= minSharpRatioGlobal
    let looksSharpCenter   = sharpRatioCenter >= minSharpRatioCenter

    return looksBlurryByVar && !(looksSharpGlobally || looksSharpCenter)
}


/// 綜合判斷是否模糊：同時看 Laplacian 變異數 + 銳利比例
/// - Parameters:
///   - image: 來源影像
///   - varianceThreshold: 變異數門檻（越低越嚴格）
///   - edgeThreshold: 以像素為單位的 Laplacian 強度門檻（用來做銳利遮罩）
///   - minSharpRatio: 銳利像素比例的下限，>= 這個比例就判定「不模糊」
/// - Returns: true 代表視為模糊
private func isBlurryByVarianceAndSharpRatio(
    _ image: UIImage,
    varianceThreshold: Float = BLUR_VARIANCE_THRESHOLD, // 你上面設 70
    edgeThreshold: Float = 4.0,   // 可調：6~12 常見
    minSharpRatio: Float = 0.2    // 你要的一半
) -> Bool {

    guard let srcCG = image.cgImage else { return false }

    // ====== 與 laplacianVarianceScore 相同的前處理 ======
    let ciIn = CIImage(cgImage: srcCG)
    let targetW: CGFloat = 224
    let sx = targetW / CGFloat(srcCG.width)
    let sy = targetW / CGFloat(srcCG.height)
    let scaled = ciIn.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

    let gray = scaled.applyingFilter("CIColorControls",
                                     parameters: [kCIInputSaturationKey: 0])

    let blurred = gray.applyingFilter("CIGaussianBlur",
                                      parameters: [kCIInputRadiusKey: 0.8])
    let inputForEdge = blurred

    let weights: [CGFloat] = [-1, -1, -1,
                              -1,  8, -1,
                              -1, -1, -1]
    guard
        let convolved = CIFilter(
            name: "CIConvolution3X3",
            parameters: [
                kCIInputImageKey: inputForEdge,
                "inputWeights": CIVector(values: weights, count: 9),
                "inputBias": 0
            ]
        )?.outputImage
    else { return false }

    let rect = CGRect(x: 0, y: 0,
                      width: Int(max(1, round(targetW))),
                      height: Int(max(1, round(targetW))))
    guard let outCG = sharedCIContext.createCGImage(convolved, from: rect) else { return false }

    let width = outCG.width
    let height = outCG.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var buffer = [UInt8](repeating: 0, count: Int(bytesPerRow * height))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &buffer,
        width: width, height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }

    ctx.draw(outCG, in: CGRect(x: 0, y: 0, width: width, height: height))

    // 轉為 Float 陣列（取 R 通道；灰階狀況 R=G=B）
    let count = width * height
    var samples = [Float](repeating: 0, count: count)
    var s = 0
    for i in stride(from: 0, to: buffer.count, by: 4) {
        samples[s] = Float(buffer[i])
        s += 1
    }

    // 1) 變異數
    var mean: Float = 0, meanSquares: Float = 0
    vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))
    vDSP_measqv(samples, 1, &meanSquares, vDSP_Length(samples.count))
    let variance = max(0, meanSquares - mean * mean)

    // 2) 銳利比例（|Laplacian| > edgeThreshold 的像素比）
    //    注意：因為我們把卷積結果轉成 8-bit，負值會被夾到 0。
    //    在這種情況下，直接用「> edgeThreshold」即可，不用取絕對值。
    var sharpCount = 0
    for v in samples where v > edgeThreshold { sharpCount += 1 }
    let sharpRatio = Float(sharpCount) / Float(max(1, count))

    // === 決策：只要超過一半區域是清晰，就不當模糊 ===
    let looksSharpByArea = sharpRatio >= minSharpRatio
    let looksBlurryByVariance = variance < varianceThreshold

    // 視為模糊 = 區域不夠清晰 且 變異數也低
    return (!looksSharpByArea) && looksBlurryByVariance
}


/// 回傳 Laplacian 影像像素的變異數：越大越清晰、越小越模糊
private func laplacianVarianceScore(_ image: UIImage) -> Float? {
    guard let srcCG = image.cgImage else { return nil }

    // 1) 縮小
    let ciIn = CIImage(cgImage: srcCG)
    let targetW: CGFloat = 224
    let sx = targetW / CGFloat(srcCG.width)
    let sy = targetW / CGFloat(srcCG.height)
    let scaled = ciIn.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

    // 2) 轉灰階
    let gray = scaled.applyingFilter("CIColorControls",
                                     parameters: [kCIInputSaturationKey: 0])

    // 3) 先做一點 Gaussian Blur 來降噪（重點在這裡）
    //    半徑 0.8~1.2 都可以，越大越嚴格（更容易判定為模糊）
    let blurred = gray.applyingFilter("CIGaussianBlur",
                                      parameters: [kCIInputRadiusKey: 0.8])
    let inputForEdge = blurred

    // 4) Laplacian 卷積
    let weights: [CGFloat] = [-1, -1, -1,
                              -1,  8, -1,
                              -1, -1, -1]
    guard
        let convolved = CIFilter(
            name: "CIConvolution3X3",
            parameters: [
                kCIInputImageKey: inputForEdge,  // ← 用降噪後的影像
                "inputWeights": CIVector(values: weights, count: 9),
                "inputBias": 0
            ]
        )?.outputImage
    else { return nil }

    // 5) 轉成 RGBA8 小圖以取得像素
    let rect = CGRect(x: 0, y: 0,
                      width: Int(max(1, round(targetW))),
                      height: Int(max(1, round(targetW))))
    guard let outCG = sharedCIContext.createCGImage(convolved, from: rect) else { return nil }

    let width = outCG.width
    let height = outCG.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var buffer = [UInt8](repeating: 0, count: Int(bytesPerRow * height))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

    ctx.draw(outCG, in: CGRect(x: 0, y: 0, width: width, height: height))

    // 6) 只取 R 通道（灰階時 R=G=B）
    var samples = [Float](repeating: 0, count: width * height)
    var s = 0
    for i in stride(from: 0, to: buffer.count, by: 4) {
        samples[s] = Float(buffer[i])
        s += 1
    }

    // 7) 變異數
    var mean: Float = 0
    var meanSquares: Float = 0
    vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))
    vDSP_measqv(samples, 1, &meanSquares, vDSP_Length(samples.count))
    return max(0, meanSquares - mean * mean)
}


// 掃描出的「模糊」結果
struct BlurryScanResult: Codable {
    var date: Date
    var assetIds: [String]      // 與當次掃描使用的順序一致
    var blurryIndices: [Int]    // 以 assetIds 的全域索引為準
}

// 一個簡單的模糊分數門檻（越小越模糊），可自行微調
private let BLUR_VARIANCE_THRESHOLD: Float = 70.0

// 把原本的 ActiveAlert 換成這個
enum ActiveAlert: Identifiable {
    case overLimit(String)
    case finished(dup: Int, blurry: Int)
    var id: String {
        switch self {
        case .overLimit: return "overLimit"
        case .finished:  return "finished"
        }
    }
}

struct PersistedScanSummary: Codable {
    var date: Date
    var duplicateCount: Int
    var duplicateGroupsByAssetIDs: [[String]]?
}

struct OverLimitAlert: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - Row

struct ResultRowView: View, Equatable {
    let category: PhotoCategory
    let total: Int
    let processed: Int
    let countsLoading: Bool
    let result: ScanResult?
    let blurry: BlurryScanResult?     // ← 由呼叫端傳入，而不是直接用外層字典

    @State private var goDetail = false

    static func == (lhs: ResultRowView, rhs: ResultRowView) -> Bool {
        lhs.category == rhs.category &&
        lhs.total == rhs.total &&
        lhs.processed == rhs.processed &&
        lhs.result?.duplicateCount == rhs.result?.duplicateCount &&
        (lhs.blurry?.blurryIndices.count ?? 0) == (rhs.blurry?.blurryIndices.count ?? 0)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.localizedName)
                    .font(.system(size: 16, weight: .semibold))

                if countsLoading && total == 0 {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.9)
                        Text("progress_loading")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(String(format: NSLocalizedString("progress_scanned", comment: ""), processed, total))
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
                Text(String(format: NSLocalizedString("result_duplicate", comment: ""), result.duplicateCount))
                    .foregroundColor(.red)
                    .font(.system(size: 14))

                NavigationLink(
                    destination: SimilarImagesEntryView(category: category, inlineResult: result),
                    isActive: $goDetail
                ) { EmptyView() }.frame(width: 0, height: 0).hidden()

                Button {
                    if let vc = UIApplication.shared.topMostVisibleViewController() {
                        //InterstitialAdManager.shared.showIfReady(from: vc) {
                        goDetail = true
                        //}
                    } else {
                        goDetail = true
                    }
                } label: {
                    Text("btn_view")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.13))
                        .cornerRadius(10)
                }

            } else {
                Text("result_no_duplicate")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }

            // 顯示「模糊」捷徑
            if let blur = blurry, !blur.blurryIndices.isEmpty {
                HStack {
                    Spacer()
                    NavigationLink {
                        // 你專案若已有 BlurryImagesEntryView，這裡直接用；若沒有，可換成 SimilarImagesView + custom groups
                        BlurryImagesEntryView(category: category, blurryResult: blur)
                    } label: {
                        HStack(spacing: 6) {
                            
                            Text(String(format: NSLocalizedString("btn_view_blurry_count", comment: ""), blur.blurryIndices.count))
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color(.black).opacity(0.07), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 4)
    }
}

// MARK: - Common

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
    case photo
    case selfie
    case portrait
    case screenshot

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .photo:      return NSLocalizedString("category_photo", comment: "")
        case .selfie:     return NSLocalizedString("category_selfie", comment: "")
        case .portrait:   return NSLocalizedString("category_portrait", comment: "")
        case .screenshot: return NSLocalizedString("category_screenshot", comment: "")
        }
    }
}

struct ScanResult: Codable {
    var date: Date
    var duplicateCount: Int
    var lastGroups: [[Int]]
    var assetIds: [String]
}

// MARK: - ContentView (UI pieces)

extension ContentView {
    var headerView: some View {
        VStack(spacing: 1) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text("app_title")
                .font(.largeTitle).bold()
                .foregroundColor(.primary)
            Text("app_subtitle")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    var categorySelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("category_select_title").font(.headline)
            Text("category_limit_hint").font(.subheadline)
            ForEach(PhotoCategory.allCases, id: \.self) { category in
                let chunks = categoryAssetChunks[category] ?? []
                let chunkCountAll = chunks.count
                let selectedIdx = selectedChunkIndex(for: category)
                let displayCount = chunkCount(for: category, idx: selectedIdx)

                HStack(spacing: 10) {
                    Button {
                        if !isProcessing { tryToggle(category) }
                    } label: {
                        Image(systemName: selectedCategories.contains(category) ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundColor(selectedCategories.contains(category) ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.localizedName).font(.system(size: 16, weight: .semibold))
                        Text(String(format: NSLocalizedString("chunk_title_count", comment: ""), selectedIdx + 1, displayCount))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()

                    if chunkCountAll > 1 {
                        Menu {
                            ForEach(0..<chunkCountAll, id: \.self) { i in
                                Button {
                                    selectedCategoryChunks[category] = i
                                    if isOverLimitCategory(category) {
                                        didChangeChunk(for: category, to: i) // >1000 強制單選
                                    } else if selectedCategories.contains(category) {
                                        let total = selectedCategories.reduce(0) { acc, cat in
                                            chunkCount(for: cat, idx: selectedCategoryChunks[cat] ?? 0) + acc
                                        }
                                        if total > 1000 {
                                            activeAlert = .overLimit(NSLocalizedString("alert_over_limit_msg", comment: ""))
                                            selectedCategories.remove(category)
                                        }
                                    }
                                } label: {
                                    Text(String(format: NSLocalizedString("chunk_title_count", comment: ""), i + 1, chunks[i].count))
                                }
                            }
                        } label: {
                            HStack {
                                Text(String(format: NSLocalizedString("chunk_menu", comment: ""), selectedIdx + 1, chunks[selectedIdx].count))
                                Image(systemName: "chevron.down")
                            }
                            .padding(.horizontal, 10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .disabled(isProcessing)
                    }
                }
                .background(selectedCategories.contains(category) ? Color.blue.opacity(0.08) : Color.clear)
                .cornerRadius(12)
                .opacity(isProcessing ? 0.6 : 1)
            }
        }
        .padding(.top, 10)
    }

    var actionButtonsView: some View {
        VStack(spacing: 15) {
            Button(action: {
                let selectedSnapshot = Array(selectedCategories)
                let chunkSnapshot = selectedCategoryChunks
                runAfterInterstitial {
                    DispatchQueue.main.async {
                        startScanMultiple(selected: selectedSnapshot, selectedChunks: chunkSnapshot)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("btn_scan_selected")
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
                    //Text(String(format: NSLocalizedString("progress_total", comment: ""), selectedProcessed, selectedTotal))
                    //    .font(.footnote).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal)
            }
        }
    }

    var scanResultsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("result_title")
                .font(.headline)
                .padding(.leading, 4)
            ForEach(PhotoCategory.allCases, id: \.self) { category in
                let result = scanResults[category]
                ResultRowView(
                    category: category,
                    total: photoVM.categoryCounts[category] ?? 0,
                    processed: processedCounts[category] ?? 0,
                    countsLoading: photoVM.countsLoading,
                    result: result,
                    blurry: blurryResults[category] // ← 正確傳入
                )
            }
        }
        .padding(.top)
    }
}

extension View {
    func card() -> some View {
        self.padding(12)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color(.black).opacity(0.07), radius: 4, x: 0, y: 2)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var blurryResults: [PhotoCategory: BlurryScanResult] = [:]

    @State private var categoryCounts: [PhotoCategory: Int] = [:]
    @State private var processedCounts: [PhotoCategory: Int] = [:]
    @State private var scanResults: [PhotoCategory: ScanResult] = [:]
    @State private var isProcessing = false
    @State private var processingIndex = 0
    @State private var processingTotal = 0
    @State private var showFinishAlert = false
    @State private var totalDuplicatesFound = 0
    @State private var countsLoading = true
    @StateObject private var photoVM = PhotoLibraryViewModel()
    @State private var selectedCategories: Set<PhotoCategory> = []

    @State private var categoryAssetChunks: [PhotoCategory: [[PHAsset]]] = [:]
    @State private var selectedCategoryChunks: [PhotoCategory: Int] = [:]

    @State private var overLimitAlert: OverLimitAlert? = nil
    @State private var activeAlert: ActiveAlert?

    // MARK: - Helper: 背景同步載圖，保證只回呼一次
    func requestImageSync(_ asset: PHAsset,
                          target: CGSize,
                          mode: PHImageContentMode = .aspectFill) -> UIImage? {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true
        opts.deliveryMode = .fastFormat
        opts.resizeMode   = .fast
        opts.isNetworkAccessAllowed = false

        var out: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: mode,
            options: opts
        ) { img, _ in out = img }
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

    private func countForCategoryInSelection(_ category: PhotoCategory) -> Int {
        isOverLimitCategory(category)
        ? chunkCount(for: category, idx: selectedChunkIndex(for: category))
        : totalCount(for: category)
    }

    private func totalCountOfSelection(_ selection: Set<PhotoCategory>) -> Int {
        selection.reduce(0) { $0 + countForCategoryInSelection($1) }
    }

    private func tryToggle(_ category: PhotoCategory) {
        if selectedCategories.contains(category) { selectedCategories.remove(category); return }

        let targetIsOver = isOverLimitCategory(category)

        if targetIsOver {
            if !selectedCategories.isEmpty {
                _ = totalCount(for: category)
                activeAlert = .overLimit(NSLocalizedString("alert_over_limit_msg", comment: ""))
                return
            }
            if selectedCategoryChunks[category] == nil { selectedCategoryChunks[category] = 0 }
            selectedCategories = [category]
            return
        }

        if let over = selectedCategories.first(where: { isOverLimitCategory($0) }) {
            _ = totalCount(for: over)
            activeAlert = .overLimit(NSLocalizedString("alert_over_limit_msg", comment: ""))
            return
        }

        var newSel = selectedCategories
        newSel.insert(category)
        let total = totalCountOfSelection(newSel)
        if total > 1000 {
            activeAlert = .overLimit(NSLocalizedString("alert_over_limit_msg", comment: ""))
        } else {
            selectedCategories = newSel
        }
    }

    private func didChangeChunk(for category: PhotoCategory, to newIndex: Int) {
        selectedCategoryChunks[category] = newIndex
        selectedCategories = [category]
    }

    private func runAfterInterstitial(_ work: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let vc = UIApplication.shared.topMostVisibleViewController() {
                InterstitialAdManager.shared.showIfReady(from: vc) {
                    DispatchQueue.main.async { work() }
                }
            } else {
                work()
            }
        }
    }

    // --- 本地快取 key
    let scanResultsKey = "ScanResults"

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerView
                            .padding(.top, 10)
                            .card()
                        categorySelectionView
                            .card()
                        globalProgressView
                        scanResultsView
                            .card()
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 8)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        actionButtonsView
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        Divider().opacity(0.15)
                        BannerAdView(adUnitID: "ca-app-pub-9275380963550837/9201898058")
                            .frame(height: 50)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .background(Color(.systemGray6))
            .navigationBarHidden(true)
            .alert(item: $activeAlert) { a in
                switch a {
                case .overLimit(let msg):
                    return Alert(
                        title: Text("alert_over_limit_title"),
                        message: Text(msg),
                        dismissButton: .default(Text("ok"))
                    )
                case .finished(let dup, let blurry):
                    // 這裡的文案會用 Localizable.strings（下段提供）
                    return Alert(
                        title: Text("alert_scan_done_title"),
                        message: Text(String(format: NSLocalizedString("alert_scan_done_message", comment: ""), dup, blurry)),
                        dismissButton: .default(Text("ok"))
                    )
                }
            }

            .onAppear {
                Task {
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    if status == .authorized || status == .limited {
                        await reloadAllData()
                    } else {
                        PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                            if newStatus == .authorized || newStatus == .limited {
                                Task { await reloadAllData() }
                            }
                        }
                    }

                    // 👇 關鍵：只在第一次進入 ContentView 時才可能顯示 Interstitial
                    if isFirstAppear {
                        if let vc = UIApplication.shared.topMostVisibleViewController() {
                            InterstitialAdManager.shared.maybeShow(from: vc)
                        } else {
                            InterstitialAdManager.shared.preload()
                        }
                        isFirstAppear = false
                    } else {
                        // 從子頁（如 SimilarImagesEntryView / BlurryImagesEntryView）返回
                        // 不顯示插頁式，保留 Banner，並適時詢問評分
                        reviewAskCounter += 1
                        // 從子頁返回 ContentView：不顯示插頁式，只顯示 Banner，並「可能」詢問評分
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            requestAppReviewIfAppropriate()
                        }
                    }
                }
            }

        }
    }

    // 初始讀取
    func reloadAllData() async {
        if let s = loadSummary() {
            for (raw, cs) in s.categories {
                if let cat = PhotoCategory(rawValue: raw) {
                    self.scanResults[cat] = ScanResult(
                        date: cs.date,
                        duplicateCount: cs.duplicateCount,
                        lastGroups: [],
                        assetIds: []
                    )
                    self.photoVM.categoryCounts[cat] = cs.totalAssetsAtScan
                }
            }
        }
        for cat in PhotoCategory.allCases {
            let assets = await fetchAssetsAsync(for: cat)
            let chunks = splitAssetsByThousand(assets)
            categoryAssetChunks[cat] = chunks
            if chunks.count > 1 { selectedCategoryChunks[cat] = 0 }
            await MainActor.run {
                self.photoVM.categoryCounts[cat] = assets.count
            }
        }
    }

    func refreshCategoryCounts() async {
        for cat in PhotoCategory.allCases {
            let assets = await fetchAssetsAsync(for: cat)
            await MainActor.run { self.photoVM.categoryCounts[cat] = assets.count }
        }
    }

    func totalSelectedAssetsCount() -> Int {
        selectedCategories.reduce(0) { acc, cat in
            let chunks = categoryAssetChunks[cat] ?? []
            let idx = (chunks.count > 1) ? (selectedCategoryChunks[cat] ?? 0) : 0
            return acc + (chunks[safe: idx]?.count ?? 0)
        }
    }

    // MARK: - 掃描

    func startChunkScan(selected: PhotoCategory?) {
        let categories = selected == nil ? PhotoCategory.allCases : [selected!]
        let chunkSnapshot = selectedCategoryChunks
        startScanMultiple(selected: categories, selectedChunks: chunkSnapshot)
    }

    // 埋點：批次抽 embedding
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

    // 一次載入多張縮圖
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
                        let img = requestImageSync(asset, target: target, mode: .aspectFill)
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

    func currentSignature(for category: PhotoCategory) async -> LibrarySignature {
        let assets = await fetchAssetsAsync(for: category)
        return makeSignature(for: assets)
    }

    func loadDetailIfAvailable(for category: PhotoCategory) async -> (assetIds: [String], groups: [[Int]])? {
        guard let detail = loadDetail(for: category) else { return nil }
        let nowSig = await currentSignature(for: category)
        if nowSig == detail.librarySignature {
            return (detail.assetIds, detail.lastGroups)
        } else {
            return (detail.assetIds, detail.lastGroups) // 可能過期
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
            let collection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
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
                selfieAssets.enumerateObjects { asset, _, _ in selfieIds.insert(asset.localIdentifier) }
            }
            let allImages = PHAsset.fetchAssets(with: .image, options: options)
            var arr: [PHAsset] = []
            allImages.enumerateObjects { asset, _, _ in
                let isSelfie = selfieIds.contains(asset.localIdentifier)
                let isPortrait = asset.mediaSubtypes.contains(.photoDepthEffect)
                let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                if !isSelfie && !isPortrait && !isScreenshot { arr.append(asset) }
            }
            completion(arr)
        }
    }


    

    // MARK: - 掃描主流程（修正 scope 與模糊偵測位置）

    func startScanMultiple(selected: [PhotoCategory], selectedChunks: [PhotoCategory: Int]) {
        var sessionDuplicatesFound = 0
        var sessionBlurryFound = 0   // ← 新增：整次掃描累計模糊張數

        guard !selected.isEmpty else { return }
        isProcessing = true

        Task {
            await MainActor.run { selected.forEach { processedCounts[$0] = 0 } }
            

            for cat in selected {
                let chunks = categoryAssetChunks[cat] ?? []
                let chunkIdx = (chunks.count > 1) ? (selectedChunks[cat] ?? 0) : 0
                let chunkAssets = chunks[safe: chunkIdx] ?? []
                if chunkAssets.isEmpty { continue }

                var seen = Set<String>()
                let uniqueAssets = chunkAssets
                    .filter { seen.insert($0.localIdentifier).inserted }
                    .sorted { ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) }

                await MainActor.run { photoVM.categoryCounts[cat] = uniqueAssets.count }

                let windowSize = 50
                let chunkSize = 250
                var prevTailEmbs: [[Float]] = []
                var prevTailIds: [String] = []
                let globalIds = uniqueAssets.map { $0.localIdentifier }

                var allGroups: [[Int]] = []
                var allAssetIds: [String] = []
                var allBlurryGlobalIndices: [Int] = []   // ← 放在 per-category 作用域

                for chunkStart in stride(from: 0, to: uniqueAssets.count, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, uniqueAssets.count)
                    let chunkSubAssets = Array(uniqueAssets[chunkStart..<chunkEnd])

                    let pairs = await loadImagesWithIds(from: chunkSubAssets)
                    let chunkIdsFiltered = pairs.map(\.id)
                    let images = pairs.map(\.image)

                    // 模糊偵測：在取得 images 之後
                    for (localIdx, img) in images.enumerated() {
                        if isBlurryAdaptiveCenterWeighted(
                            img,
                            varianceThreshold: 40,     // 60~90 看你要多嚴
                            kStd: 0.6,                 // 0.8~1.5：越大越嚴格
                            minSharpRatioGlobal: 0.10, // 全圖 12% 有明顯邊緣就不當模糊
                            minSharpRatioCenter: 0.15, // 中央 25% 有明顯邊緣就不當模糊
                            gaussianRadius: 0.5
                        ) {
                            let globalIdx = chunkStart + localIdx
                            allBlurryGlobalIndices.append(globalIdx)
                        }

                    }


                    let embs = await batchExtractEmbeddingsChunked(images: images)
                    let allEmbs = prevTailEmbs + embs
                    let allIds  = prevTailIds + chunkIdsFiltered
                    var pairsIndices: [(Int, Int)] = []

                    for i in prevTailEmbs.count..<allEmbs.count {
                        for j in max(0, i - windowSize)..<i {
                            if cosineSimilarity(allEmbs[i], allEmbs[j]) >= 0.90 {
                                pairsIndices.append((j, i))
                            }
                        }
                    }

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

                    await MainActor.run {
                        scanResults[cat] = ScanResult(
                            date: Date(),
                            duplicateCount: allGroups.flatMap { $0 }.count,
                            lastGroups: allGroups,
                            assetIds: allAssetIds
                        )
                        processedCounts[cat, default: 0] += chunkSubAssets.count
                    }

                    if embs.count > windowSize {
                        prevTailEmbs = Array(embs.suffix(windowSize))
                        prevTailIds  = Array(chunkIdsFiltered.suffix(windowSize))
                    } else {
                        prevTailEmbs = embs
                        prevTailIds  = chunkIdsFiltered
                    }
                }

                await MainActor.run {
                    scanResults[cat] = ScanResult(
                        date: Date(),
                        duplicateCount: allGroups.flatMap { $0 }.count,
                        lastGroups: allGroups,
                        assetIds: allAssetIds
                    )
                    // 存模糊結果
                    let uniqueBlurry = Array(Set(allBlurryGlobalIndices)).sorted()
                    blurryResults[cat] = BlurryScanResult(
                        date: Date(),
                        assetIds: globalIds,
                        blurryIndices: uniqueBlurry
                    )
                    saveScanResultsToLocal()
                    sessionDuplicatesFound += allGroups.flatMap { $0 }.count
                    sessionBlurryFound += uniqueBlurry.count              // ← 加總到本次
                }

                let signature = makeSignature(for: uniqueAssets)
                let detail = ScanDetailV2(
                    category: cat.rawValue,
                    date: Date(),
                    assetIds: allAssetIds,
                    lastGroups: allGroups,
                    librarySignature: signature
                )
                saveDetail(detail, for: cat)

                var existing = loadSummary() ?? PersistedScanSummaryV2(categories: [:])
                existing.categories[cat.rawValue] = .init(
                    date: Date(),
                    duplicateCount: allGroups.flatMap { $0 }.count,
                    totalAssetsAtScan: uniqueAssets.count,
                    librarySignature: signature
                )
                saveSummary(existing)
            }

            await MainActor.run {
                isProcessing = false
                totalDuplicatesFound = sessionDuplicatesFound
                activeAlert = .finished(dup: sessionDuplicatesFound, blurry: sessionBlurryFound)
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
                        cont.resume(returning: [:]); return
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

// MARK: - 小工具

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

final class PhotoLibraryWatcher: NSObject, PHPhotoLibraryChangeObserver, ObservableObject {
    @Published var bump: Int = 0
    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in self?.bump &+= 1 }
    }
}

// 假設你在 SimilarImagesView 有類別資訊 category
func applyLocalDeletionToCache(category: PhotoCategory, deletedIDs: [String]) {
    guard var detail = loadDetail(for: category) else { return }
    let toDelete = Set(deletedIDs)
    var newIndexMap: [Int: Int] = [:]
    var newAssetIds: [String] = []
    for (i, id) in detail.assetIds.enumerated() {
        if !toDelete.contains(id) {
            newIndexMap[i] = newAssetIds.count
            newAssetIds.append(id)
        }
    }
    var newGroups: [[Int]] = []
    for g in detail.lastGroups {
        let mapped = g.compactMap { newIndexMap[$0] }
        if mapped.count >= 2 { newGroups.append(mapped) }
    }
    detail.assetIds   = newAssetIds
    detail.lastGroups = newGroups
    detail.librarySignature = LibrarySignature(
        assetCount: newAssetIds.count,
        firstID: newAssetIds.first,
        lastID: newAssetIds.last
    )
    saveDetail(detail, for: category)

    if var s = loadSummary() {
        if var cs = s.categories[category.rawValue] {
            cs.duplicateCount = newGroups.flatMap{$0}.count
            cs.totalAssetsAtScan = newAssetIds.count
            cs.librarySignature = detail.librarySignature
            s.categories[category.rawValue] = cs
            saveSummary(s)
        }
    }
}

#Preview {
    ContentView()
}


