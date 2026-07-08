import SwiftUI
import CryptoKit
import SwiftData

struct ChatView: View {
    
    @ObservedObject var webRTC: WebRTCManager
        
    @State private var pubKey: String = ""
    
    @State private var text = ""
    
    @Environment(\.modelContext) private var modelContext
    
    @Query var messages: [Message]
       
    init(webRTC: WebRTCManager, searchTarget: String, searchTarget2: String) {
        self.webRTC = webRTC
        
        _messages = Query(filter: #Predicate<Message> { msg in
            // Condition 1: searchTarget sent it to searchTarget2
            (msg.from == searchTarget && msg.to == searchTarget2) ||
            // Condition 2: searchTarget2 sent it to searchTarget
            (msg.from == searchTarget2 && msg.to == searchTarget)
        }, sort: \Message.timestamp)
    }

    
    var body: some View {
        
        VStack {
            
            ScrollView {
                ForEach(messages) { msg in
                    VStack {
                        if msg.from == webRTC.connectedTo {
                            Text("Other")
                        } else {
                            Text("You")
                        }
                        
                        Text(msg.content)
                    }
                }
            }
            
            HStack {
                TextField("Message", text:$text)
                Button("Send") {
                    
                    let msg = Message(content: text, from: pubKey, to: webRTC.connectedTo)
                    modelContext.insert(msg)
                    
                    if let enc = encryptP2PMessage(text, peerPublicKeyBase64: webRTC.connectedTo) {
                        webRTC.send(Event(
                            type: .send, payload: enc
                        ))
                    } else {
                        print("Could not encrypt message")
                    }
                }
            }
        }
        .onAppear {
            let key = loadP256KeyAgreementPrivateKey(account:Config.appGroupIdentifier)
            if let publicKey = key?.publicKey {
                pubKey = publicKey.rawRepresentation.base64EncodedString()
            }
            
            
            webRTC.onMessage = { message in
                guard message.type == .send else { return }
                
                if let content = decryptP2PMessage(message.payload, peerPublicKeyBase64: webRTC.connectedTo) {
                    DispatchQueue.main.async {
                        let newMsg = Message(content: content, from:webRTC.connectedTo, to: webRTC.localClientId)
                        modelContext.insert(newMsg)
                    }
                }
            }

        }
    }
}
