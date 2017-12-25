//
//  CloudKitAccountService.swift
//  CalendarMemo_iOS
//
//  Created by JeeJuseong on 2017-12-12.
//  Copyright © 2017 Sanppo. All rights reserved.
//
/* usage
private let account = Account()
account
	.status
	.asDriver(onErrorJustReturn: .couldNotDetermine)
	.map { (accountStatus) -> String in
		switch accountStatus {
		case .couldNotDetermine: return "Unable to Determine iCloud Account Status"
		case .available: return "User Signed in to iCloud"
		case .restricted: return "Not Permitted to Access iCloud Account"
		case .noAccount: return "User Not Signed in to iCloud"
		}
	}
	.drive(accountStatusLabel.rx.text)
	.disposed(by: disposeBag)
*/

import RxSwift
import RxCocoa
import CloudKit

class Account {

	// MARK: - Properties
	private let container = Cloud().container

	// MARK: -
	private let _status = BehaviorRelay<CKAccountStatus>(value: .couldNotDetermine)

	public var status: Observable<CKAccountStatus> { return _status.asObservable() }

	// MARK: - Initialization
	init() {
		// Request Account Status
		requestAccountStatus()

		// Setup Notification Handling
		setupNotificationHandling()
	}

	// MARK: - Notification Handling
	@objc private func accountDidChange(_ notification: Notification) {
		// Request Account Status
		DispatchQueue.main.async { self.requestAccountStatus() }
	}

	// MARK: - Helper Methods
	private func requestAccountStatus() {
		// Request Account Status
		container.accountStatus { [unowned self] (status, error) in
			// Print Errors
			if let error = error { print(error) }

			// Update Account Status
			print(status.rawValue)
			self._status.accept(status)
		}

	}

	// MARK: -
	fileprivate func setupNotificationHandling() {
		// Helpers
		let notificationCenter = NotificationCenter.default
		notificationCenter.addObserver(self, selector: #selector(accountDidChange(_:)), name: Notification.Name.CKAccountChanged, object: nil)
	}

}
