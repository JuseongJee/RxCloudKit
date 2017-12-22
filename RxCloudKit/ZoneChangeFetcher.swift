//
//  ZoneFetcher.swift
//  RxCloudKit
//
//  Created by Maxim Volgin on 11/08/2017.
//  Copyright © 2017 Maxim Volgin. All rights reserved.
//

import RxSwift
import CloudKit
import os.log

public enum ZoneEvent {
    case changed(CKRecordZoneID)
    case deleted(CKRecordZoneID)
    case token(CKServerChangeToken)
}

final class ZoneChangeFetcher {
    
    typealias Observer = AnyObserver<ZoneEvent>
    
    private let observer: Observer
    private let database: CKDatabase
    private let limit: Int
    
    private var serverChangeToken: CKServerChangeToken?
    
    init(observer: Observer, database: CKDatabase, previousServerChangeToken: CKServerChangeToken?, limit: Int) {
        self.observer = observer
        self.database = database
        self.limit = limit
        self.serverChangeToken = previousServerChangeToken
        self.fetch()
    }
    
    // MARK:- callbacks
    
    private func recordZoneWithIDChangedBlock(zoneID: CKRecordZoneID) {
        self.observer.on(.next(.changed(zoneID)))
    }
    
    private func recordZoneWithIDWasDeletedBlock(zoneID: CKRecordZoneID) {
        self.observer.on(.next(.deleted(zoneID)))
    }
    
    private func changeTokenUpdatedBlock(serverChangeToken: CKServerChangeToken) {
        self.serverChangeToken = serverChangeToken
        self.observer.on(.next(.token(serverChangeToken)))
    }
    
    private func fetchDatabaseChangesCompletionBlock(serverChangeToken: CKServerChangeToken?, moreComing: Bool, error: Error?) {

				switch CKResultHandler.resultType(with: error) {
				case .success:
					self.serverChangeToken = serverChangeToken
					if moreComing {
						self.fetch()
					} else {
						observer.on(.completed)
					}
				case .retry(let timeToWait, _):
					self.serverChangeToken = serverChangeToken
					CKResultHandler.retryOperationIfPossible(retryAfter: timeToWait, block: {
						self.fetch()
						return
					})
				case .recoverableError(let reason):
					switch reason {
					case .changeTokenExpired(let message):
						/// The previousServerChangeToken value is too old and the client must re-sync from scratch
						os_log("changeTokenExpired: %@", log: Log.zoneChangeFetcher, type: .error, message)
						self.serverChangeToken = nil
						self.fetch()
					default:
						return
					}
				case .fail(let reason):
					observer.on(.error(reason))
				default:
					return
				}

    }
    
    // MARK:- custom
    
    private func fetch() {
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: self.serverChangeToken)
        operation.resultsLimit = self.limit
        operation.fetchAllChanges = true
        operation.qualityOfService = .userInitiated
        operation.changeTokenUpdatedBlock = self.changeTokenUpdatedBlock
        operation.recordZoneWithIDChangedBlock = self.recordZoneWithIDChangedBlock
        operation.recordZoneWithIDWasDeletedBlock = self.recordZoneWithIDWasDeletedBlock
				operation.fetchDatabaseChangesCompletionBlock = self.fetchDatabaseChangesCompletionBlock
        self.database.add(operation)
    }
    
}
