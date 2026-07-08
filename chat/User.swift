import Foundation
import Security
import CryptoKit

enum Config {
    static let appGroupIdentifier = "com.bryce.chat"
    static var sharedDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupIdentifier)
    }
}

struct User {
    
    var publicKey: String
    let privateKey: String
    
}
