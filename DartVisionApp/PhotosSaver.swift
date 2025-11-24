//  PhotosSaver.swift
//  Speichert UIImages in die Fotos-App und (optional) in ein bestimmtes Album.
//  Benötigt im Info.plist: NSPhotoLibraryAddUsageDescription

import UIKit
import Photos

public enum PhotosSaver {
    /// Speichert ein UIImage in die Fotos-App und sortiert es in ein Album.
    /// - Parameters:
    ///   - image: Das zu speichernde Bild.
    ///   - albumName: Zielalbum (wird bei Bedarf angelegt). Standard: "DartImages".
    ///   - completion: Ergebnis mit PHAsset oder Error.
    public static func save(_ image: UIImage,
                            toAlbum albumName: String = "DartImages",
                            completion: ((Result<PHAsset, Error>) -> Void)? = nil) {
        requestAddOnlyIfNeeded { granted in
            guard granted else {
                completion?(.failure(PhotosSaverError.authorizationDenied))
                return
            }
            createAsset(from: image) { result in
                switch result {
                case .failure(let err):
                    completion?(.failure(err))
                case .success(let asset):
                    // Album optional einsortieren
                    ensureAlbum(named: albumName) { album in
                        guard let album = album else {
                            completion?(.success(asset)) // Gespeichert, aber ohne Album
                            return
                        }
                        add(asset: asset, to: album) { ok in
                            if ok {
                                completion?(.success(asset))
                            } else {
                                completion?(.failure(PhotosSaverError.couldNotInsertIntoAlbum))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Internals

private extension PhotosSaver {
    enum PhotosSaverError: LocalizedError {
        case authorizationDenied
        case couldNotCreateAsset
        case couldNotFetchCreatedAsset
        case couldNotCreateAlbum
        case couldNotInsertIntoAlbum

        var errorDescription: String? {
            switch self {
            case .authorizationDenied: return "Keine Berechtigung, um in die Fotos-App zu schreiben."
            case .couldNotCreateAsset: return "Konnte Foto-Asset nicht erstellen."
            case .couldNotFetchCreatedAsset: return "Konnte erstelltes Foto-Asset nicht laden."
            case .couldNotCreateAlbum: return "Konnte Album nicht erstellen."
            case .couldNotInsertIntoAlbum: return "Konnte Foto nicht ins Album einsortieren."
            }
        }
    }

    static func requestAddOnlyIfNeeded(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        default:
            completion(false)
        }
    }

    static func createAsset(from image: UIImage,
                            completion: @escaping (Result<PHAsset, Error>) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }, completionHandler: { success, error in
            if !success || error != nil {
                completion(.failure(error ?? PhotosSaverError.couldNotCreateAsset))
                return
            }
            // Letztes aufgenommenes Asset holen (sicherste Variante: nach Erstellzeit sortieren)
            let fetch = PHAsset.fetchAssets(with: .image, options: {
                let o = PHFetchOptions()
                o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                o.fetchLimit = 1
                return o
            }())
            if let asset = fetch.firstObject {
                completion(.success(asset))
            } else {
                completion(.failure(PhotosSaverError.couldNotFetchCreatedAsset))
            }
        })
    }

    static func ensureAlbum(named title: String,
                            completion: @escaping (PHAssetCollection?) -> Void) {
        if let existing = fetchAlbum(named: title) {
            completion(existing)
            return
        }
        // Album erstellen
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholder = req.placeholderForCreatedAssetCollection
        }, completionHandler: { success, error in
            guard success, error == nil, let id = placeholder?.localIdentifier else {
                completion(nil)
                return
            }
            let coll = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
            completion(coll)
        })
    }

    static func fetchAlbum(named title: String) -> PHAssetCollection? {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "localizedTitle = %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: opts).firstObject
    }

    static func add(asset: PHAsset,
                    to album: PHAssetCollection,
                    completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            if let req = PHAssetCollectionChangeRequest(for: album) {
                req.addAssets([asset] as NSArray)
            }
        }, completionHandler: { success, _ in
            completion(success)
        })
    }
}
