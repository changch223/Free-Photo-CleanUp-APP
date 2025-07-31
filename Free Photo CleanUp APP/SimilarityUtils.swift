//
//  SimilarityUtils.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-30.
//
import Foundation

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    let dot = zip(a, b).map(*).reduce(0, +)
    let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
    return dot / (normA * normB + 1e-8)
}

func findSimilarPairs(embeddings: [[Float]], threshold: Float = 0.50, window: Int = 50) -> [(Int, Int)] {
    var pairs: [(Int, Int)] = []
    let n = embeddings.count
    for i in 0..<n {
        // 只跟自己後面 window 張比
        let start = i + 1
        let end = min(i + window, n - 1)
        if start > end { continue }
        for j in start...end {
            let sim = cosineSimilarity(embeddings[i], embeddings[j])
            if sim >= threshold {
                pairs.append((i, j))
            }
        }
    }
    return pairs
}

