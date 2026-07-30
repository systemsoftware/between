import SwiftUI
import SwiftData


struct ContentView: View {
 
    @StateObject var webRTC = WebRTCManager()
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    
    @Query var messages: [Message]
    
    @Query var contacts: [Contact]
    
    @State var showWipeAlert = false
    
    @State var isTyping = false
    
    @State var tab = ""
    
    func incomingName(for peerId: String?) -> String {
        return contacts.first(where: { $0.webRTCId == peerId })?.humanName
            ?? peerId
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
                        .navigationTitle("Connect")
                } else {
                    if webRTC.enableAudio {
                        CallView(webRTC: webRTC, searchTarget: webRTC.connectedTo)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                }
            }.tabItem {
                Image(systemName: "bubble")
            }
            .tag("Connect")
            
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
                tab = "Connect"
                webRTC.connectionDecisionCallback?(true)
                webRTC.connectedTo = webRTC.incomingConnectionPeerId ?? ""
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
        .onAppear {
            webRTC.modelContext = modelContext
            
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
                    } else if event.type == .endCall {
                        webRTC.disconnect()
                        webRTC.connectedTo = ""
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if !webRTC.isPeerConnected {
                    webRTC.register()
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
