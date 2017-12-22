//
//  Log.swift
//  RxCloudKit
//
//  Created by Maxim Volgin on 02/11/2017.
//  Copyright © 2017 Maxim Volgin. All rights reserved.
//

import os.log

struct Log {
    fileprivate static let subsystem: String = Bundle.main.bundleIdentifier ?? ""
    
    static let cache = OSLog(subsystem: subsystem, category: "cache")
	static let recordChangeFetcher = OSLog(subsystem: subsystem, category: "recordChangeFetcher")
	static let zoneChangeFetcher = OSLog(subsystem: subsystem, category: "zoneChangeFetcher")

}
