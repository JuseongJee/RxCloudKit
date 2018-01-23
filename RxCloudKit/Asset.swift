//
//  Asset.swift
//  RxCloudKit
//
//  Created by JeeJuseong on 2018-01-16.
//  Inspired By Fu Yuan from IceCream
//  Copyright © 2018 Maxim Volgin. All rights reserved.
//


import Foundation
import CloudKit

public protocol RxCKAsset: RxCKRecord {
	var uniqueFileName: String { get set }
	static func assetNameKeyPrefix() -> String
	static func assetDefaultURL() -> URL
}

extension RxCKAsset {

	// for not saving this property, so func
	public static func assetNameKeyPrefix() -> String {
		return "\(Self.self)_filename_"
	}

	var asset: CKAsset? {
		get {
			if FileManager.default.fileExists(atPath: Self.assetDefaultURL().appendingPathComponent(uniqueFileName).path ) {
				return CKAsset(fileURL: Self.assetDefaultURL().appendingPathComponent(uniqueFileName))
			} else {
				return nil
			}
		}
	}

	///This is for recreate a path. The old path will be deleted.
	public mutating func setData(id: String, data: Data) {
		uniqueFileName = "\(id)_\(UUID().uuidString)"
		setData(data: data)
	}

	mutating func setData(path: String, data: Data) {
		self.uniqueFileName = path
		setData(data: data)
	}

	private func setData(data: Data) {
		let dataPath = Self.assetDefaultURL().appendingPathComponent(uniqueFileName)
		do {
			try data.write(to: dataPath)
		} catch {
			print("Error writing avatar to temporary directory: \(error)")
		}
	}

	public func getData() -> Data? {
		let filePath = Self.assetDefaultURL().appendingPathComponent(uniqueFileName)
		do {
			return try Data(contentsOf: filePath )
		} catch {
			return nil
		}

	}

	/*
	static func parse(from propName: String, record: CKRecord, asset: CKAsset) -> Self? {
		let assetPathKey = propName + Self.assetNameKeyPrefix()
		guard let assetPathValue = record.value(forKey: assetPathKey) as? String else { return nil }
		guard let assetData = NSData(contentsOfFile: asset.fileURL.path) as Data? else { return nil }
		let asset = Self
		asset.localPath = assetPathValue
		// Local cache not exist, save it to local files
		if !Self.assetFilePaths().contains(assetPathValue) {
			try! assetData.write(to: Self.assetDefaultURL().appendingPathComponent(assetPathValue))
		}
		return asset
	}*/

}

extension RxCKAsset {

	// The default path for the storing of RxAsset. That is:
	// xxx/Document/RxAssetStructName/
	public static func assetDefaultURL() -> URL {
		let documentDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
		let commonAssetPath = documentDir.appendingPathComponent(Self.type)
		if !FileManager.default.fileExists(atPath: commonAssetPath.path) {
			do {
				try FileManager.default.createDirectory(atPath: commonAssetPath.path, withIntermediateDirectories: false, attributes: nil)
			} catch {

			}
		}
		return commonAssetPath
	}

	// Fetch all Asset files' path
	public static func assetFilePaths() -> [String] {
		do {
			return try FileManager.default.contentsOfDirectory(atPath: Self.assetDefaultURL().path)
		} catch  {
			print("Error to get RxAsset assetFilesPaths")
		}
		return [String]()
	}

	// Execute delete
	private static func delete(files: [String]){
		for fileName in files {
			let absolutePath = Self.assetDefaultURL().appendingPathComponent(fileName).path
			do {
				print("deleteCacheFiles.removeItem:", absolutePath)
				try FileManager.default.removeItem(atPath: absolutePath)
			} catch {
				print(error)
			}
		}
	}

	// When delete an object. We need to delete related RxAsset files
	public static func deleteAssetFile(with id: String) {
		let needToDeleteCacheFiles = Self.assetFilePaths().filter { $0.contains(id) }
		delete(files: needToDeleteCacheFiles)
	}

	// This step will only delete the local files which are not exist in iCloud. CKRecord to compare with local cache files, continue to keep local files which iCloud's record are still exists.
	public static func removeRedundantCacheFiles(record: CKRecord) {
		DispatchQueue.global(qos: .background).async {
			let idForThisRecord: String = record.value(forKey: "id") as! String
			// Which must have value in iCloud
			var allCloudAssetStringValues = [String]()
			// Local files, which must relate with this record's id
			var allLocalRelateCacheFiles = [String]()

			// Get all iCloud exist files' name
			let allKeys = record.allKeys()
			for key in allKeys {
				if key.contains(Self.assetNameKeyPrefix()) {
					let valueA = record.value(forKey: key) as? String
					if let value = valueA, value != "" {
						allCloudAssetStringValues.append(value)
					}
				}
			}
			let allCacheFilePaths = Self.assetFilePaths()
			for fileName in allCacheFilePaths {
				if fileName.contains(idForThisRecord) {
					allLocalRelateCacheFiles.append(fileName)
				}
			}
			var needToDeleteCacheFiles = [String]()
			for cacheFile in allLocalRelateCacheFiles {
				if !allCloudAssetStringValues.contains(cacheFile) {
					needToDeleteCacheFiles.append(cacheFile)
				}
			}

			delete(files: needToDeleteCacheFiles)
		}
	}

}
