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
	static func assetKeyPrefix() -> String
	static func assetDefaultURL() -> URL
}

extension RxCKAsset {
	/** read from CKRecord */
	public mutating func read(from record: CKRecord) {
		self.readMetadata(from: record)
		self.readUserFields(from: record)
		self.parseAssetFields(record: record)
	}

	// for not saving this property, so func
	public static func assetKeyPrefix() -> String {
		return "RxCKAssetFilename_"
	}

	public func assetKey() -> String {
		return "\(Self.assetKeyPrefix())\(Self.reordType)"
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
	public mutating func setData(self_id: String, data: Data) {
		uniqueFileName = "\(self_id)"
		setData(data: data)
	}

	public mutating func setData(path: String, data: Data) {
		self.uniqueFileName = path
		setData(data: data)
	}

	private func setData(data: Data) {
		guard uniqueFileName != "" else { return }

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

	mutating func parseAssetFields(record: CKRecord) {
		let assetPathKey = self.assetKey()
		guard let recordFilename = record.value(forKey: "uniqueFileName") as? String else { return }
		uniqueFileName = recordFilename
		guard let asset = record.value(forKey: assetPathKey) as? CKAsset else { return }
		guard let assetData = NSData(contentsOfFile: asset.fileURL.path) as Data? else { return }

		// Local cache not exist, save it to local files
		if !Self.assetFilePaths().contains(uniqueFileName) {
			try! assetData.write(to: Self.assetDefaultURL().appendingPathComponent(uniqueFileName))
		}
	}

}

extension RxCKAsset {

	// The default path for the storing of RxAsset. That is:
	// xxx/Document/RxAssetStructName/
	public static func assetDefaultURL() -> URL {
		let documentDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
		let commonAssetPath = documentDir.appendingPathComponent(Self.reordType)
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
				if key.contains(Self.assetKeyPrefix()) {
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
