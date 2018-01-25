//
//  CKErrorHandler.swift
//  CalendarMemo_iOS
//
//  Modified by JeeJuseong on 2017-14-12.
//  Copyright © 2017 Sanppo. All rights reserved.
//
//  Created by Randy Carney on 10/19/17.
//  Copyright © 2017 randycarney. All rights reserved.
//
//

import Foundation
import CloudKit
import os.log

/*
This struct returns an explicit CKErrorType binned according to the CKErorr.Code,
updated to the current Apple documentation CloudKit > CKError > CKError.Code
https://developer.apple.com/documentation/cloudkit/ckerror.code

You can implement this class by switching on the handleCKError function and appropriately handling the relevant errors pertaining to the specific CKOperation.

Check SyncEngine for current implementation:

SyncEngine.fetchChangesInDatabase.fetchDatabaseChangesCompletionBlock

SyncEngine.fetchChangesInZone.recordZoneFetchCompletionBlock

SyncEngine.createCustomZone

SyncEngine.createDatabaseSubscription

SyncEngine.syncRecordsToCloudKit
*/

/*
This is a more detailed implementation of
EVCloudKitDao: https://github.com/evermeer/EVCloudKitDao
from github user evermeer: https://github.com/evermeer

The original handleCloudKitErrorAs() func can be found here:
https://github.com/evermeer/EVCloudKitDao/blob/master/Source/EVCloudKitDao.swift

A more detailed implementation of the EVCloudKitDao suitable to IceCream would be useful. He has a ton of great features working and the source code is mostly documented.
http://cocoadocs.org/docsets/EVCloudKitDao/3.1.0/index.html
*/

public struct ResultHandler {

	// MARK: - Public API
	public enum CKOperationResultType {
		case success
		case retry(afterSeconds: Double, message: String)
		case chunk
		case recoverableError(reason: CKOperationFailReason)
		case fail(reason: CKOperationFailReason)
	}

	// I consider the following speciality cases the most likely to be specifically and separately addressed by custom code in the adopting class
	public enum CKOperationFailReason: Error {
		case changeTokenExpired(String)
		case network(String)
		case quotaExceeded(String)
		case partialFailure(String)
		case serverRecordChanged(String)
		case shareRelated(String)
		case unhandledErrorCode(String)
		case unknown(String)
	}

	public struct ErrorMessageForUser {
		var message: String
		var buttonTitle: String
	}

	// swiftlint:disable cyclomatic_complexity
	static public func resultType(with error: Error?) -> CKOperationResultType {
		guard error != nil else { return .success }

		guard let e = error as? CKError else {
			return .fail(reason: .unknown("The error returned is not a CKError"))
		}

		let message = ResultHandler.returnErrorMessage(for: e.code)

		switch e.code {

		// SHOULD RETRY
		case .serviceUnavailable,
			 .requestRateLimited,
			 .zoneBusy:

			// If there is a retry delay specified in the error, then use that.
			let userInfo = e.userInfo
			if let retry = userInfo[CKErrorRetryAfterKey] as? Double {
				os_log("ErrorHandler - %@. Should retry in %@ seconds.", log: Log.cache, type: .error, message, retry)
				return .retry(afterSeconds: retry, message: message)
			} else {
				return .fail(reason: .unknown(message))
			}

		// RECOVERABLE ERROR
		case .networkUnavailable,
			 .networkFailure:
			os_log("ErrorHandler.recoverableError: %@", log: Log.cache, type: .error, message)
			return .recoverableError(reason: .network(message))
		case .changeTokenExpired:
			os_log("ErrorHandler.recoverableError: %@", log: Log.cache, type: .error, message)
			return .recoverableError(reason: .changeTokenExpired(message))
		case .serverRecordChanged:
			os_log("ErrorHandler.recoverableError: %@", log: Log.cache, type: .error, message)
			return .recoverableError(reason: .serverRecordChanged(message))
		case .partialFailure:
			// Normally it shouldn't happen since if CKOperation `isAtomic` set to true
			if let dictionary = e.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary {
				os_log("ErrorHandler.partialFailure: for $@ items; CKPartialErrorsByItemIDKey: %@", log: Log.cache, type: .error, dictionary.count, dictionary)
			}
			return .recoverableError(reason: .partialFailure(message))

		// SHOULD CHUNK IT UP
		case .limitExceeded:
			os_log("ErrorHandler.Chunk: %@", log: Log.cache, type: .error, message)
			return .chunk

		// SHARE DATABASE RELATED
		case .alreadyShared,
			 .participantMayNeedVerification,
			 .referenceViolation,
			 .tooManyParticipants:
			os_log("ErrorHandler.Fail: %@", log: Log.cache, type: .error, message)
			return .fail(reason: .shareRelated(message))
		// quota exceeded is sort of a special case where the user has to take action(like spare more room in iCloud) before retry
		case .quotaExceeded:
			os_log("ErrorHandler.Fail: %@", log: Log.cache, type: .error, message)
			return .fail(reason: .quotaExceeded(message))
		// FAIL IS THE FINAL, WE REALLY CAN'T DO MORE
		default:
			os_log("ErrorHandler.Fail: %@", log: Log.cache, type: .error, message)
			return .fail(reason: .unknown(message))

		}

	}

	static public func retryOperationIfPossible(retryAfter: Double, block: @escaping () -> ()) {

		let delayTime = DispatchTime.now() + retryAfter
		DispatchQueue.main.asyncAfter(deadline: delayTime, execute: {
			block()
		})

	}

	static private func returnErrorMessage(for code: CKError.Code) -> String {
		var returnMessage = ""

		switch code {
		case .alreadyShared:
			returnMessage = "Already Shared: a record or share cannot be saved because doing so would cause the same hierarchy of records to exist in multiple shares."
		case .assetFileModified:
			returnMessage = "Asset File Modified: the content of the specified asset file was modified while being saved."
		case .assetFileNotFound:
			returnMessage = "Asset File Not Found: the specified asset file is not found."
		case .badContainer:
			returnMessage = "Bad Container: the specified container is unknown or unauthorized."
		case .badDatabase:
			returnMessage = "Bad Database: the operation could not be completed on the given database."
		case .batchRequestFailed:
			returnMessage = "Batch Request Failed: the entire batch was rejected."
		case .changeTokenExpired:
			returnMessage = "Change Token Expired: the previous server change token is too old."
		case .constraintViolation:
			returnMessage = "Constraint Violation: the server rejected the request because of a conflict with a unique field."
		case .incompatibleVersion:
			returnMessage = "Incompatible Version: your app version is older than the oldest version allowed."
		case .internalError:
			returnMessage = "Internal Error: a nonrecoverable error was encountered by CloudKit."
		case .invalidArguments:
			returnMessage = "Invalid Arguments: the specified request contains bad information."
		case .limitExceeded:
			returnMessage = "Limit Exceeded: the request to the server is too large."
		case .managedAccountRestricted:
			returnMessage = "Managed Account Restricted: the request was rejected due to a managed-account restriction."
		case .missingEntitlement:
			returnMessage = "Missing Entitlement: the app is missing a required entitlement."
		case .networkUnavailable:
			returnMessage = "Network Unavailable: the internet connection appears to be offline."
		case .networkFailure:
			returnMessage = "Network Failure: the internet connection appears to be offline."
		case .notAuthenticated:
			returnMessage = "Not Authenticated: to use this app, you must enable iCloud syncing. Go to device Settings, sign in to iCloud, then in the app settings, be sure the iCloud feature is enabled."
		case .operationCancelled:
			returnMessage = "Operation Cancelled: the operation was explicitly canceled."
		case .partialFailure:
			returnMessage = "Partial Failure: some items failed, but the operation succeeded overall."
		case .participantMayNeedVerification:
			returnMessage = "Participant May Need Verification: you are not a member of the share."
		case .permissionFailure:
			returnMessage = "Permission Failure: to use this app, you must enable iCloud syncing. Go to device Settings, sign in to iCloud, then in the app settings, be sure the iCloud feature is enabled."
		case .quotaExceeded:
			returnMessage = "Quota Exceeded: saving would exceed your current iCloud storage quota."
		case .referenceViolation:
			returnMessage = "Reference Violation: the target of a record's parent or share reference was not found."
		case .requestRateLimited:
			returnMessage = "Request Rate Limited: transfers to and from the server are being rate limited at this time."
		case .serverRecordChanged:
			returnMessage = "Server Record Changed: the record was rejected because the version on the server is different."
		case .serverRejectedRequest:
			returnMessage = "Server Rejected Request"
		case .serverResponseLost:
			returnMessage = "Server Response Lost"
		case .serviceUnavailable:
			returnMessage = "Service Unavailable: Please try again."
		case .tooManyParticipants:
			returnMessage = "Too Many Participants: a share cannot be saved because too many participants are attached to the share."
		case .unknownItem:
			returnMessage = "Unknown Item:  the specified record does not exist."
		case .userDeletedZone:
			returnMessage = "User Deleted Zone: the user has deleted this zone from the settings UI."
		case .zoneBusy:
			returnMessage = "Zone Busy: the server is too busy to handle the zone operation."
		case .zoneNotFound:
			returnMessage = "Zone Not Found: the specified record zone does not exist on the server."
		default:
			returnMessage = "Unhandled Error."
		}

		return returnMessage + "CKError.Code: \(code.rawValue)"
	}
	// swiftlint:enable cyclomatic_complexity

}
