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

func findSimilarPairs(embeddings: [[Float]], threshold: Float = 0.50) -> [(Int, Int)] {
    var pairs: [(Int, Int)] = []
    for i in 0..<embeddings.count {
        for j in (i+1)..<embeddings.count {
            let sim = cosineSimilarity(embeddings[i], embeddings[j])
            if sim >= threshold {
                pairs.append((i, j))
            }
        }
    }
    return pairs
}
