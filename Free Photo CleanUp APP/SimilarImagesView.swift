//
//  SimilarImagesView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-30.
//

import SwiftUI

struct SimilarImagesView: View {
    let similarPairs: [(Int, Int)]
    let images: [UIImage]

    var body: some View {
        List {
            ForEach(Array(similarPairs.enumerated()), id: \.offset) { index, pair in
                HStack {
                    Image(uiImage: images[pair.0])
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                    Image(systemName: "arrow.right")
                    Image(uiImage: images[pair.1])
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                }
            }
        }
        .navigationTitle("Similar Photos")
    }
}

