import Foundation
import SwiftData

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
