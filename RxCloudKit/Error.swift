//
//  Errors.swift
//  RxCloudKit
//
//  Created by Maxim Volgin on 22/06/2017.
//  Copyright © 2017 Maxim Volgin. All rights reserved.
//

import RxSwift

public enum SerializationError: Error {
    case structRequired
	case noMetadata
    case unknownEntity(name: String)
    case unsupportedSubType(label: String?)
	case containsNotSavedRecordInProperty(propertyName: String)
}
