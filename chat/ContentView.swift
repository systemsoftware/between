import SwiftUI
import SwiftData


struct ContentView: View {
 
    @StateObject var webRTC = WebRTCManager()
    @Environment(\.modelContext) var modelContext
    
    @State var showWipeAlert = false
    
    var body: some View {
        NavigationStack {
            if !webRTC.isPeerConnected {
                ConnectView(webRTC: webRTC)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture(count: 3) {
                        showWipeAlert = true
                    }
            } else {
                ChatView(webRTC: webRTC, searchTarget: webRTC.connectedTo, searchTarget2: webRTC.localClientId)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture(count: 3) {
                        showWipeAlert = true
                    }
                    .alert("What do you want to wipe?", isPresented: $showWipeAlert) {
                        wipeAlert()
                    }
            }
        }
        .onAppear {
            webRTC.onMessage = { event in
                DispatchQueue.main.async {
                    if event.type == .send {
                        if let decrypted = decryptP2PMessage(event.payload, peerPublicKeyBase64: webRTC.connectedTo) {
                            let replyingTo: UUID? = event.replyingTo.flatMap { UUID(uuidString: $0) }
                            let msg = Message(content: decrypted, from: webRTC.connectedTo, to: webRTC.localClientId, event:event.id, replyingTo:replyingTo)
                            modelContext.insert(msg)
                            try? modelContext.save()
                        }
                    } else if event.type == .delete {
                        let targetID = UUID(uuidString:event.payload)
                        do {
                            try modelContext.delete(model: Message.self, where: #Predicate { object in
                                object.event == targetID
                            })
                            try modelContext.save()
                        } catch {
                            print("Failed to delete: \(error)")
                        }
                    }
                }
            }
        }
    }
    
}

struct wipeAlert: View {
    
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        Button("Messages") {
            Task {
                do {
                    try modelContext.delete(model: Message.self)
                    try modelContext.save()
                } catch {
                    print(error)
                }
            }
        }
        Button("Contacts") {
            Task {
                do {
                    try modelContext.delete(model: Contact.self)
                    try modelContext.save()
                } catch {
                    print(error)
                }
            }
        }
        Button("Cancel", role: .cancel) {
            
        }
        
    }
    
}
