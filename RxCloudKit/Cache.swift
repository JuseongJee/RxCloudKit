//
//  Cache.swift
//  RxCloudKit
//
//  Created by Maxim Volgin on 10/08/2017.
//  Copyright © 2017 Maxim Volgin. All rights reserved.
//

/*
// Example of completeCashing()
// if any changes happened in other device, the linked sub objects have been saved on cloud
// but client received the changed records with no sub objects but only the information of the relation. ie. '*_refid' or '*_refids'
// when sub objects' information are changed, there's nothing to do more in other codes
// So, to sum it up. Relation changed -> Relation information changed, relation itself not received -> Rebuild the relations in this func
public func completeCashing() {
	let realm = try! Realm(configuration: RealmConfig.config)
	let memos = realm.objects(MemoRlmObject.self)
	var resultMemos = Array<MemoRlmObject>()

	for memo in Array(memos.filter("label_refid != nil AND label = nil")) {
		print(memo)
		if let label_refid = memo.label_refid {
			let memoLabel = realm.objects(MemoLabelRlmObject.self).filter("uid = %@", label_refid).first
			let index = resultMemos.index(where: { $0.uid == memo.uid })
			let newMemo: MemoRlmObject
			if let index = index {
				newMemo = MemoRlmObject(value: resultMemos.remove(at: index))
			} else {
				newMemo = MemoRlmObject(value: memo)
			}
			newMemo.label = memoLabel
			resultMemos.append(newMemo)
		}
	}

	// Querying Lists containing primitive values is currently not supported.
	for memo in Array(memos.filter("labels.@count = 0")).filter({ !$0.labels_refids.isEmpty }) {
		let memoLabels = Array(realm.objects(MemoLabelRlmObject.self).filter("uid IN %@", memo.labels_refids))
		let index = resultMemos.index(where: { $0.uid == memo.uid })
		let newMemo: MemoRlmObject
		if let index = index {
			newMemo = MemoRlmObject(value: resultMemos.remove(at: index))
		} else {
			newMemo = MemoRlmObject(value: memo)
		}
		newMemo.labels.append(objectsIn: memoLabels)

		resultMemos.append(newMemo)
	}


	//update resultMemos array to local database
}
*/
import os.log
import RxSwift
import CloudKit

public protocol CacheDelegate {
    // private db
    func cache(record: CKRecord)
    func deleteCache(for recordID: CKRecordID)
    func deleteCache(in zoneID: CKRecordZoneID)
    // any db (via subscription)
    func query(notification: CKQueryNotification, fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
	// call after all cashing projects are done
	func completeCashing()
}

public final class Cache {

    static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let privateSubscriptionID = "\(appName).privateDatabaseSubscriptionID"
    static let sharedSubscriptionID = "\(appName).sharedDatabaseSubscriptionID"
    static let privateTokenKey = "\(appName).privateDatabaseTokenKey"
    static let sharedTokenKey = "\(appName).sharedDatabaseTokenKey"
    static let zoneTokenMapKey = "\(appName).zoneTokenMapKey"

    public let cloud = Cloud()
    public let zoneIDs: [String]
    public let local = Local()

    private let delegate: CacheDelegate
    private let disposeBag = DisposeBag()
    private var cachedZoneIDs: [CKRecordZoneID] = []
//    private var missingZoneIDs: [CKRecordZoneID] = []

    public init(delegate: CacheDelegate, zoneIDs: [String]) {
        self.delegate = delegate
        self.zoneIDs = zoneIDs
    }

    public func applicationDidFinishLaunching(fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void = { _ in }) {

        let zones = zoneIDs.map({ Zone.create(name: $0) })

        cloud
            .privateDB
            .rx
            .modify(recordZonesToSave: zones, recordZoneIDsToDelete: nil).subscribe { event in
                switch event {
                case .success(let (saved, deleted)):
                    os_log("saved", log: Log.cache, type: .info)
                case .error(let error):
                    os_log("error: %@", log: Log.cache, type: .error, error.localizedDescription)
                }
            }
            .disposed(by: disposeBag)

        if let subscriptionId = self.local.subscriptionID(for: Cache.privateSubscriptionID) {
//            cloud
//                .privateDB
//                .rx
//                .fetch(with: subscriptionId)
            // TODO
            //                        let subscription = CKDatabaseSubscription.init(subscriptionID: Cache.privateSubscriptionID)
        } else {

            let subscription = CKDatabaseSubscription()
            let notificationInfo = CKNotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo

            cloud
                .privateDB
                .rx
                .modify(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil).subscribe { event in
                    switch event {
                    case .success(let (saved, deleted)):
                        os_log("saved", log: Log.cache, type: .info)
                        if let subscriptions = saved {
                            for subscription in subscriptions {
                                self.local.save(subscriptionID: subscription.subscriptionID, for: Cache.privateSubscriptionID)
                            }
                        }
                    case .error(let error):
                        os_log("error: %@", log: Log.cache, type: .error, error.localizedDescription)
                    }
                }
                .disposed(by: disposeBag)
        }

        // TODO same for shared

        //let createZoneGroup = DispatchGroup()
        //createZoneGroup.enter()
        //self.createZoneGroup.leave()
//        createZoneGroup.notify(queue: DispatchQueue.global()) {
//        }

        self.fetchDatabaseChanges(fetchCompletionHandler: completionHandler)
		self.resumeLongLivedOperations()

    }

    public func applicationDidReceiveRemoteNotification(userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let dict = userInfo as! [String: NSObject]
        let notification = CKNotification(fromRemoteNotificationDictionary: dict)
        
        switch notification.notificationType {
        case CKNotificationType.query:
            let queryNotification = notification as! CKQueryNotification
            self.delegate.query(notification: queryNotification, fetchCompletionHandler: completionHandler)
        case CKNotificationType.database:
            self.fetchDatabaseChanges(fetchCompletionHandler: completionHandler)
        case CKNotificationType.readNotification:
            // TODO
            break
        case CKNotificationType.recordZone:
            // TODO
            break
        }
    }

    public func fetchDatabaseChanges(fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let token = self.local.token(for: Cache.privateTokenKey)
        cloud.privateDB.rx.fetchChanges(previousServerChangeToken: token).subscribe { event in
            switch event {
            case .next(let zoneEvent):
                print("\(zoneEvent)")

                switch zoneEvent {
                case .changed(let zoneID):
                    os_log("changed: %@", log: Log.cache, type: .info, zoneID)
                    self.cacheChanged(zoneID: zoneID)
                case .deleted(let zoneID):
                    os_log("deleted: %@", log: Log.cache, type: .info, zoneID)
                    self.delegate.deleteCache(in: zoneID)
                case .token(let token):
                    os_log("token: %@", log: Log.cache, type: .info, token)
                    self.local.save(token: token, for: Cache.privateTokenKey)
                    self.processAndPurgeCachedZones(fetchCompletionHandler: completionHandler)
                }

            case .error(let error):
                os_log("error: %@", log: Log.cache, type: .error, error.localizedDescription)
                completionHandler(.failed)
            case .completed:

                if self.cachedZoneIDs.count == 0 {
                    completionHandler(.noData)
                }

            }
        }.disposed(by: disposeBag)
    }

    public func fetchZoneChanges(recordZoneIDs: [CKRecordZoneID], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        var optionsByRecordZoneID: [CKRecordZoneID: CKFetchRecordZoneChangesOptions] = [:]

        let tokenMap = self.local.zoneTokenMap(for: Cache.zoneTokenMapKey)
        for recordZoneID in recordZoneIDs {
            if let token = tokenMap[recordZoneID] {
                let options = CKFetchRecordZoneChangesOptions()
                options.previousServerChangeToken = token
                optionsByRecordZoneID[recordZoneID] = options
            }
        }

        cloud
            .privateDB
            .rx
            .fetchChanges(recordZoneIDs: recordZoneIDs, optionsByRecordZoneID: optionsByRecordZoneID).subscribe { event in
                switch event {
                case .next(let recordEvent):
                    print("\(recordEvent)")

                    switch recordEvent {
                    case .changed(let record):
                        os_log("changed: %@", log: Log.cache, type: .info, record)
                        self.delegate.cache(record: record)
                    case .deleted(let recordID):
                        os_log("deleted: %@", log: Log.cache, type: .info, recordID)
                        self.delegate.deleteCache(for: recordID)
                    case .token(let (zoneID, token)):
                        os_log("token: %@", log: Log.cache, type: .info, "\(zoneID)->\(token)")
                        self.local.save(zoneID: zoneID, token: token, for: Cache.zoneTokenMapKey)
                    }

                case .error(let error):
                    os_log("error: %@", log: Log.cache, type: .error, error.localizedDescription)
                    completionHandler(.failed)
                case .completed:
                    completionHandler(.newData)
					self.delegate.completeCashing()
                }
            }
            .disposed(by: disposeBag)
    }

    public func cacheChanged(zoneID: CKRecordZoneID) {
        self.cachedZoneIDs.append(zoneID)
    }

    public func processAndPurgeCachedZones(fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard !self.cachedZoneIDs.isEmpty else {
            completionHandler(.noData)
            return
        }

        let recordZoneIDs = self.cachedZoneIDs
        self.cachedZoneIDs = []
        self.fetchZoneChanges(recordZoneIDs: recordZoneIDs, fetchCompletionHandler: completionHandler)
    }

	public func resumeLongLivedOperations() {
		//https://developer.apple.com/documentation/cloudkit/ckoperation
		cloud.container.fetchAllLongLivedOperationIDs(completionHandler: { (operationIDs, error) in
			if let error = error {
				os_log("Error fetching long lived operations: %@", log: Log.cache, type: .error, error.localizedDescription)
				// Handle error
				return
			}
			guard let identifiers = operationIDs else { return }
			for operationID in identifiers {
				self.cloud.container.fetchLongLivedOperation(withID: operationID, completionHandler: { (operation, error) in
					if let error = error {
						os_log("Error fetching operation: %@\n%@", log: Log.cache, type: .error, operationID, error.localizedDescription)
						// Handle error
						return
					}
					guard let operation = operation else { return }
					// Add callback handlers to operation
					self.cloud.container.add(operation)
				})
			}
		})
	}

}
