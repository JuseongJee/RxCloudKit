//
//  Entities.swift
//  RxCloudKit
//
//  Created by Maxim Volgin on 22/06/2017.
//  Copyright © 2017 Maxim Volgin. All rights reserved.
//

import CloudKit
import ObjectiveC

public protocol RxCKRecord {

    /** record type */
    static var reordType: String { get } // must be implemented by struct

    /** zone name */
    static var zone: String { get } // must be implemented by struct

    /** system fields */
    var metadata: Data? { get set }

	/** mark to determine the record is saved in the cloud */
	var savedOnCloud: Bool { get set }

    /** reads user fields */
    mutating func readUserFields(from record: CKRecord) // must be implemented by struct

    /** copies user fields via reflection */
    func writeUserFields(to record: CKRecord) throws

    /** read system and user fields form CKRecord */
    mutating func read(from record: CKRecord)

    /** generate CKRecord with user- and possibly system fields filled */
    func asCKRecord() throws -> CKRecord

	/** generate CKRecord's arry from properties, for saving all ckrecords in one record */
	func asCKRecords() throws -> [CKRecord]

    /** predicate to uniquely identify the record, such as: NSPredicate(format: "code == '\(code)'") */
    func predicate() -> NSPredicate

    /** custom recordName if desired (must be unique per DB) */
    func recordName() -> String?

	static func from(ckRecord: CKRecord) -> Self

	/* For the static initializer functions like init(fillNewMeta: Bool) or from(ckRecord: CKRecord), there should be an initializer which has no parameter in the structs which adopt this RxCKRecord Protocol */
	init()
}

//var AssociatedObjectHandle: UInt8 = 0

public extension RxCKRecord {

//    public var metadata: Data? {
//        get {
//            return objc_getAssociatedObject(self, &AssociatedObjectHandle) as? Data
//        }
//        set {
//            objc_setAssociatedObject(self, &AssociatedObjectHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
//        }
//    }

    /** CloudKit recordName (if metadata != nil) */
    public func id() -> String? {
        return self.fromMetadata()?.recordID.recordName
    }

    /** read from CKRecord */
    public mutating func read(from record: CKRecord) {
        self.readMetadata(from: record)
        self.readUserFields(from: record)
    }

    /** as CKRecord (will init metadata if metadata == nil ) */
	public func asCKRecord() throws -> CKRecord {

		guard metadata == nil else{
			throw SerializationError.noMetadata
		}

		let record: CKRecord = self.fromMetadata()!
        try self.writeUserFields(to: record)
        return record
    }

    /**  query on CKRecord system field(s) with NSArray.filtered(using: predicate) */
    public static func predicate(block: @escaping (CKRecord) -> Bool) -> NSPredicate {
        return NSPredicate { (object, bindings) -> Bool in
            if let entity = object {
                if let rxCKRecord = entity as? Self {
                    if let ckRecord = rxCKRecord.fromMetadata() {
                        return block(ckRecord)
                    }
                }
            }
            return false
        }
    }

	public func recordName() -> String? {
		return nil
	}

	public static func from(ckRecord: CKRecord) -> Self {
		var ret = Self.init()
		ret.read(from: ckRecord)
		return ret
	}

	/* for the CKReference, every RxCkRecords should be initialized with metadata */
	init(fillNewMeta: Bool) {
		self.init()
		if fillNewMeta {
			self.metadata = Self.newMetadata()
		}
	}

    /** CloudKit zoneID */
    public static var zoneID: CKRecordZoneID {
        get {
            return CKRecordZone(zoneName: Self.zone).zoneID
        }
    }

    /** create empty CKRecord for zone and type (and name, if provided via .recordName() method) */
    public static func newCKRecord(name: String? = nil) -> CKRecord {
        if let recordName = name {
            let id = CKRecordID(recordName: recordName, zoneID: Self.zoneID)
            let record = CKRecord(recordType: Self.reordType, recordID: id)
            return record
        } else {
            let record = CKRecord(recordType: Self.reordType, zoneID: Self.zoneID)
            return record
        }
    }


    /** create empty CKRecord with name for type */
    public static func create(name: String) -> CKRecord {
        let id = CKRecordID(recordName: name)
        let record = CKRecord(recordType: Self.reordType, recordID: id)
        return record
    }

    public mutating func readMetadata(from record: CKRecord) {
        self.metadata = Self.getMetaData(from: record)
    }

	public mutating func fillNewMetadata() {
		readMetadata(from: Self.newCKRecord(name: nil))
	}

	public static func newMetadata() -> Data {
		return Self.getMetaData(from: Self.newCKRecord(name: nil))
	}

	public static func getMetaData(from record: CKRecord) -> Data {
		let data = NSMutableData()
		let coder = NSKeyedArchiver.init(forWritingWith: data)
		coder.requiresSecureCoding = true
		record.encodeSystemFields(with: coder)
		coder.finishEncoding()
		return data as Data
	}

    public func fromMetadata() -> CKRecord? {
        guard self.metadata != nil else {
            return nil
        }
        let coder = NSKeyedUnarchiver(forReadingWith: self.metadata!)
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    public func writeUserFields(to record: CKRecord) throws {
        let mirror = Mirror(reflecting: self)
        if let displayStyle = mirror.displayStyle {
            guard displayStyle == .struct else {
                throw SerializationError.structRequired
            }

			if let rxCKAsset = self as? RxCKAsset {
				if let asset = rxCKAsset.asset {
					record.setValue(asset, forKey: rxCKAsset.assetKey())
				} else {
					print("no data file exists for RxCkAsset \(Self.reordType)")
				}
			}

            for case let (label?, anyValue) in mirror.children {
                if label == "metadata" || label.hasSuffix("_refid") || label.hasSuffix("_refids") {
                    continue
                }

				let anyValue = unwrap(anyValue)

				if let value = anyValue as? RxCKRecord {
					guard value.metadata != nil, value.savedOnCloud else {
						throw SerializationError.containsNotSavedRecordInProperty(propertyName: label)
					}

					let ckRecord = try value.asCKRecord()
					record.setValue(CKReference(recordID: ckRecord.recordID, action: .none), forKey: label)

				} else if let valueArray = anyValue as? Array<RxCKRecord> {
					var newArray = Array<CKReference>()
					for var element in valueArray {

						guard element.metadata != nil, element.savedOnCloud else {
							throw SerializationError.containsNotSavedRecordInProperty(propertyName: label)
						}

						let ckRecords = try element.asCKRecords()
						let ckRecord = ckRecords.last!
						newArray.append(CKReference(recordID: ckRecord.recordID, action: .none))

					}

					if newArray.count > 0 {
						record.setValue(newArray, forKey: label)
					}
				} else if anyValue is Array<String>
					|| anyValue is Array<Int>
					|| anyValue is Array<Double>
					|| anyValue is Array<CLLocation>
					|| anyValue is Array<Data>
				{
					if let valueArray = anyValue as? Array<Any> {
						var newArray = Array<Any>()
						for element in valueArray {
							newArray.append(element)
						}

						if newArray.count > 0 {
							record.setValue(newArray, forKey: label)
						}
					}
				} else if let value = anyValue as? CKRecordValue {
                    record.setValue(value, forKey: label)
                } else {
                    throw SerializationError.unsupportedSubType(label: label)
                }

            }
        }
    }

	private func unwrap<T>(_ any: T) -> Any {
		let mirror = Mirror(reflecting: any)
		guard mirror.displayStyle == .optional, let first = mirror.children.first else {
			return any
		}
		return unwrap(first.value)
	}

	public func asCKRecords() throws -> [CKRecord] {
		guard metadata != nil else {
			throw SerializationError.noMetadata
		}

		let record: CKRecord = self.fromMetadata()!
		var recordsArray = [CKRecord]()

		let mirror = Mirror(reflecting: self)
		if let displayStyle = mirror.displayStyle {
			guard displayStyle == .struct else {
				throw SerializationError.structRequired
			}


			if let rxCKAsset = self as? RxCKAsset {
				if let asset = rxCKAsset.asset {
					record.setValue(asset, forKey: rxCKAsset.assetKey())
				} else {
					print("no data file exists for RxCkAsset \(Self.reordType)")
				}
			}

			for case let (label?, anyValue) in mirror.children {
				if label == "metadata" || label.hasSuffix("_refid") || label.hasSuffix("_refids") {
					continue
				}

				let anyValue = unwrap(anyValue)

				if var value = anyValue as? RxCKRecord {

					if value.metadata == nil {
						try value.fillNewMetadata()
					}

					let ckRecords = try value.asCKRecords()
					let ckRecord = ckRecords.last!
					record.setValue(CKReference(recordID: ckRecord.recordID, action: .none), forKey: label)
					record.setValue(ckRecord.recordID.recordName, forKey: "\(label)_refid")
					recordsArray.append(contentsOf: ckRecords)

				} else if let valueArray = anyValue as? Array<RxCKRecord> {
					var refArray = Array<CKReference>()
					var refIdArray = Array<String>()
					for var element in valueArray {

						if element.metadata == nil {
							try element.fillNewMetadata()
						}

						let ckRecords = try element.asCKRecords()
						let ckRecord = ckRecords.last!
						refArray.append(CKReference(recordID: ckRecord.recordID, action: .none))
						refIdArray.append(ckRecord.recordID.recordName)
						recordsArray.append(contentsOf: ckRecords)

					}

					if refArray.count > 0 {
						record.setValue(refArray, forKey: label)
						record.setValue(refIdArray, forKey: "\(label)_refids")
					}
				} else if anyValue is Array<String>
					|| anyValue is Array<Int>
					|| anyValue is Array<Double>
					|| anyValue is Array<CLLocation>
					|| anyValue is Array<Data>
				{
					if let valueArray = anyValue as? Array<Any> {
						var newArray = Array<Any>()
						for element in valueArray {
							newArray.append(element)
						}

						if newArray.count > 0 {
							record.setValue(newArray, forKey: label)
						}
					}
				} else if let value = anyValue as? CKRecordValue {
					record.setValue(value, forKey: label)
				} else {
//					throw SerializationError.unsupportedSubType(label: label)
				}

			}
		}

		recordsArray.append(record)
		return recordsArray
	}

}
