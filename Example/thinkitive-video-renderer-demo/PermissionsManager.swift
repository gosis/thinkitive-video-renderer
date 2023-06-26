//
//  TAPermissionManager.swift
//  TestApp
//
//  Created by Gints Osis on 08/05/2019.
//  Copyright © 2019 EsPats. All rights reserved.
//

import Foundation
import Photos

class PermissionManager: NSObject {
    
    func hasPermission() -> Bool {
        return false
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        completion(false)
    }
}

class PhotosPermissionManager: PermissionManager {
    
    override func hasPermission() -> Bool {
        let permission = PHPhotoLibrary.authorizationStatus().rawValue
        return permission == PHAuthorizationStatus.authorized.rawValue
    }
    
    override func requestPermission(completion: @escaping (Bool) -> Void) {
        
        PHPhotoLibrary.requestAuthorization { status in
            completion(status.rawValue == PHAuthorizationStatus.authorized.rawValue)
        }
    }
}

// subclass for Other permissions
