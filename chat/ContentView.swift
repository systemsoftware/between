import SwiftUI
import SwiftData


struct ContentView: View {
 
    @StateObject var webRTC = WebRTCManager()
    @StateObject var callWebRTC = WebRTCManager(enableAudio: true)
    @Environment(\.modelContext) var modelContext
    
    @Query var messages: [Message]
    
    @Query var contacts: [Contact]
    
    @State var showWipeAlert = false
    
    @State var isTyping = false
    
    @State var tab = ""
    
    func incomingName(for peerId: String?) -> String {
        let cleanId = peerId?.replacingOccurrences(of: "-call", with: "")
        return contacts.first(where: { $0.webRTCId == cleanId })?.humanName
            ?? cleanId
            ?? "Someone"
    }
    
    var body: some View {
        TabView(selection:$tab) {
            NavigationStack {
                if !webRTC.isPeerConnected {
                    ConnectView(webRTC: webRTC, tab: $tab)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture(count: 3) {
                            showWipeAlert = true
                        }
                        .navigationTitle("Text")
                } else {
                    ChatView(webRTC: webRTC, searchTarget: webRTC.connectedTo, searchTarget2: webRTC.localClientId, isTyping:$isTyping)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture(count: 3) {
                            showWipeAlert = true
                        }
                        .alert("What do you want to wipe?", isPresented: $showWipeAlert) {
                            wipeAlert()
                        }
                }
            }.tabItem {
                Image(systemName: "bubble")
            }
            .tag("Text")
            
            NavigationStack {
                if !callWebRTC.isPeerConnected {
                    ConnectView(webRTC: callWebRTC, tab:$tab)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle("Call")
                } else {
                    CallView(webRTC: callWebRTC, searchTarget: callWebRTC.connectedTo)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.tabItem {
                Image(systemName: "phone")
            }
            .tag("Call")
            
            ContactsView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                }
                .tag("Contacts")
            
            HistoryView(webRTC: webRTC)
                .tabItem {
                    Image(systemName: "clock")
                }
                .tag("History")
        }
        .alert("Incoming Connection", isPresented: $webRTC.showConnectionAlert) {
            Button("Accept") {
                tab = "Text"
                webRTC.connectionDecisionCallback?(true)
                webRTC.connectedTo = webRTC.incomingConnectionPeerId?.replacingOccurrences(of: "-call", with: "") ?? ""
                webRTC.connectionDecisionCallback = nil
                webRTC.incomingConnectionPeerId = nil
            }
            Button("Reject", role: .cancel) {
                webRTC.connectionDecisionCallback?(false)
                webRTC.connectionDecisionCallback = nil
                webRTC.incomingConnectionPeerId = nil
            }
            
        } message: {
            Text("\(incomingName(for: webRTC.incomingConnectionPeerId)) is requesting a \(webRTC.incomingConnectionType).")
        }
        .alert("Incoming Connection", isPresented: $callWebRTC.showConnectionAlert) {
            Button("Accept") {
                tab = "Call"
                callWebRTC.connectionDecisionCallback?(true)
                callWebRTC.connectedTo = callWebRTC.incomingConnectionPeerId?.replacingOccurrences(of: "-call", with: "") ?? ""
                callWebRTC.connectionDecisionCallback = nil
                callWebRTC.incomingConnectionPeerId = nil
            }
            Button("Reject", role: .cancel) {
                callWebRTC.connectionDecisionCallback?(false)
                callWebRTC.connectionDecisionCallback = nil
                callWebRTC.incomingConnectionPeerId = nil
            }
        } message: {
            Text("\(incomingName(for: callWebRTC.incomingConnectionPeerId)) is requesting a \(callWebRTC.incomingConnectionType).")
        }
        .onAppear {
            webRTC.modelContext = modelContext
            callWebRTC.modelContext = modelContext
            
            callWebRTC.onMessage = { event in
                DispatchQueue.main.async {
                    if event.type == .endCall {
                        callWebRTC.disconnect()
                        callWebRTC.connectedTo = ""
                    }
                }
            }
            
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
                    } else if event.type == .typing {
                        isTyping = event.payload == "true"
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
