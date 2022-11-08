//
//  UUIDKey.swift
//  Gripr
//
//  Created by Matt Gaidica on 11/8/22.
//

import Foundation
import CoreBluetooth

// remember to whitelist chars in didDiscoverServices
class GriprPeripheral: NSObject {
    public static let GriprServiceUUID            = CBUUID.init(string: "A200")
    public static let LoadCharacteristicUUID      = CBUUID.init(string: "A201")
}
