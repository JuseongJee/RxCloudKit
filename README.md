# RxCloudKit is based on RxSwift

Basic usage.

```swift

privateDB.rx.save(record: ckRecord).subscribe { event in
    switch event {
        case .success(let record):
            print("record: ", record)
        case .error(let error):
            print("Error: ", error)
    }
}.disposed(by: Global.disposeBag)
```

"RxCKRecord" class provides syntactic sugar for copying data  (including CloudKit metadata) between CKRecord objects and plain structs. 

```swift
struct MyRecord {
    var myField: String
}

extension MyRecord: RxCKRecord {
    static var zone = "MyZone"
    static var type = "MyType"
    mutating func readUserFields(from record: CKRecord) {
        // TODO 
    }
}
```

"Cache" class is an out of the box solution for maintaining a local cache of CloudKit records. Tokens are stored in UserDefaults.

```swift
var cache: Cache {
    return Cache(delegate: self, zoneIDs: ["MyZone"])
}

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    // Override point for customization after application launch.
    application.registerForRemoteNotifications()
    self.cache.applicationDidFinishLaunching()
    return true
}

func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    self.cache.applicationDidReceiveRemoteNotification(userInfo: userInfo, fetchCompletionHandler: completionHandler)
}
```

```swift
extension AppDelegate: CacheDelegate {

    public func cache(record: CKRecord) {
        // TODO store record in CoreData
    }

    public func deleteCache(for recordID: CKRecordID) {
        // TODO delete record in CoreData
    }

    public func deleteCache(in zoneID: CKRecordZoneID) {
        // TODO delete everything relevant to zone in CoreData
    }

}
```




