import Foundation
import SwiftData

let DEFAULT_SIGNAL_SERVER = "ws://192.168.1.89:3030"

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


enum EventTypes: String, Codable {
    case send = "send"
    case delete = "delete"
    case offer = "offer"
    case answer = "answer"
    case candidate = "candidate"
    case incoming = "incoming"
}

struct Event: Codable, Identifiable {
    var id = UUID()
    var type: EventTypes
    var payload: String
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
      var content: String
    var from: String
    var to: String
    var timestamp: Date
      
    init(id: UUID = UUID(), content: String, from: String, to: String) {
          self.id = id
          self.content = content
          self.from = from
          self.to = to
        self.timestamp = Date()
      }
}

@Model
final class Contact {
    @Attribute(.unique) var id: UUID
      var webRTCId: String
    var humanName: String
    @Attribute(.externalStorage) var image: Data?
    var timestamp: Date
      
    init(id: UUID = UUID(), webRTCid: String, humanName:String, image: Data? = nil) {
          self.id = id
          self.webRTCId = webRTCid
        self.humanName = humanName
        self.image = image
        self.timestamp = Date()
      }
}
