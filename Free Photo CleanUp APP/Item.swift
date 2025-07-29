//
//  Item.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-07-28.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
