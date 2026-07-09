import Foundation
import SwiftData

let DEFAULT_SIGNAL_SERVER = "ws://150.230.37.157:3030/"

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
    var replyingTo: String?
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
      var content: String
    var from: String
    var to: String
    var timestamp: Date
    var event: UUID?
    var replyingTo: UUID?
      
    init(id: UUID = UUID(), content: String, from: String, to: String, event:UUID, replyingTo:UUID?) {
          self.id = id
          self.content = content
          self.from = from
          self.to = to
        self.event = event
        self.replyingTo = replyingTo
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
