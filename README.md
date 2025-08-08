# Smart AI Photo Cleaner

**Instantly find and delete duplicate photos. Clean up your library, free up storage, and keep only your best memories — smarter and faster!**

---

## Overview

**Smart Photo Cleaner** makes it easy to scan your photo library, detect duplicate or similar photos using on-device AI, and delete them with a single tap.

> All scanning and processing happen locally on your device. Your photos are never uploaded, ensuring full privacy and security.

---

## Features

- **Lightning-fast scanning**  
  Analyze thousands of photos in seconds with efficient batch processing and Core ML models.

- **Organized by category**  
  Automatically group your photos into categories like:
  - Selfies
  - Portraits
  - Screenshots
  - General Photos

- **Smart duplicate detection**  
  Uses image embeddings + cosine similarity to find similar or repeated photos.

- **Private & Secure**  
  All photo processing happens entirely on-device. No cloud upload, no risk.

- **Bulk cleanup made easy**  
  Select entire categories or groups and delete clutter with a single tap.

- **Instant results**  
  View scan progress and the number of duplicates found per category in real-time.

---

## Tech Stack

- **Language:** Swift + SwiftUI  
- **Frameworks:** CoreML, Vision, Photos  
- **Model:** Custom Core ML model (e.g. ResNet50 Headless, FastViT)  
- **Embedding:** Cosine similarity between image embeddings  
- **Data Persistence:** Codable structs saved to disk  
- **UI:** Native iOS app with dynamic grouping, filtering, and deletion interface  

---

## Privacy First

- **No photo leaves your device**  
- **No cloud or external API required**  
- **All models run locally using Apple CoreML and Vision**

---

## How It Works

- Fetches assets from local photo library via `PHAsset`
- Embeds images using CoreML Vision requests (`VNCoreMLRequest`)
- Compares similarity using **cosine similarity**
- Groups similar images using graph clustering
- UI lets users **keep best**, delete the rest (with swipe gestures or bulk actions)

---

## How It Works

Free Photo CleanUp APP/
├── ContentView.swift # Main UI logic
├── PhotoUtils.swift # Asset fetching, embedding
├── SimilarImagesView.swift # Grouped duplicates interface
├── DiskIO.swift # Summary & detail save/load
├── Models.swift # Codable model structs
├── ImageDiskCache.swift # Optional image caching
├── Core ML Model/ # Embedded ML models
├── Localizable.strings # Multi-language support
└── Assets.xcassets # App icons, theme


---

## Keywords

`duplicate photos`, `photo cleaner`, `storage`, `photo delete`, `cleanup`, `selfie`, `organize`, `storage saver`

---

## Download

> Coming soon on the [App Store](https://apps.apple.com/)  

---

## Author

Developed by **Chiawei Chang**  
GitHub: [@changch223](https://github.com/changch223)



