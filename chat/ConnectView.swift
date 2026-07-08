import SwiftUI
import CryptoKit
import SwiftData
import UIKit

struct ConnectView: View {
    
    @ObservedObject var webRTC: WebRTCManager
        
    @State private var pubKey: String = ""
    
    @State private var connectTo = ""
    
    @AppStorage("signalServer", store:Config.sharedDefaults) var signalServer = DEFAULT_SIGNAL_SERVER
    
    @State var showHistory = false
    @State var showReset = false
    
    @Environment(\.modelContext) var modelContext
    @Query var messages: [Message]
    
    @Query var contacts: [Contact]
    
    @State var showError = false
    @State var errorText = ""
    
    @State var status = ""
    
    @State var connected = false
        
    var body: some View {
                
        VStack(spacing: 24) {
            // Public Key
            VStack(alignment: .leading, spacing: 8) {
                Text("Your ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(pubKey)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = pubKey
                }
            }

            // Connection
            VStack(spacing: 16) {

                
                VStack {
                        Label("Signaling Server", systemImage:"server.rack")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        TextField("URL", text: $signalServer)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            connected = false
                            if let url = URL(string:signalServer) {
                                status = "Setting signaling server"
                                webRTC.setSignalingServer(url)
                                status = "Pinging signaling server"
                                Task {
                                    let reachable = await ping(url)
                                    
                                    if reachable {
                                        status = "Registering with signaling server"
                                        webRTC.register()
                                        status = "Connected to signaling server"
                                        connected = true
                                    } else {
                                        errorText = "Signaling server not reachable"
                                        showError = true
                                        status = ""
                                    }
                                }
                            } else {
                                errorText = "Invalid URL"
                                status = ""
                                showError = true
                            }
                        } label: {
                            Image(systemName: "arrow.right.to.line.compact")
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack{
                    Label("User ID", systemImage:"person")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("User ID", text: $connectTo)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Button {
                        if let url = URL(string:signalServer) {
                            status = "Setting signaling server"
                            webRTC.setSignalingServer(url)
                            status = "Pinging signaling server"
                            Task {
                                let reachable = await ping(url)
                                
                                if reachable {
                                    status = "Registering with signaling server"
                                    webRTC.register()
                                    status = "Connecting..."
                                    webRTC.connectedTo = connectTo
                                    webRTC.connect(toUserId: connectTo)
                                } else {
                                    status = ""
                                    errorText = "Signaling server not reachable"
                                    showError = true
                                }
                            }
                    }
                } label: {
                    Label("Connect", systemImage: "arrow.right.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)

                
                if !status.isEmpty {
                    HStack {
                        if !connected {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Text(status)
                            .frame(alignment: .center)
                        Spacer()
                    }
                }
                
            }
            .padding(20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))

        }
        .padding()
        .animation(.smooth, value: connectTo)
        .alert("Alert",isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorText)
        }
        .onAppear {
            guard let url = URL(string:signalServer) else {
                errorText = "Invalid URL"
                status = ""
                showError = true
                return
            }
            status = "Setting signaling server"
            webRTC.setSignalingServer(url)
            status = "Set signaling server"
            let key = loadP256KeyAgreementPrivateKey(account:Config.appGroupIdentifier)
            if let publicKey = key?.publicKey {
                pubKey = publicKey.rawRepresentation.base64EncodedString()
                webRTC.localClientId = pubKey
                status = "Registering with signaling server"
                webRTC.register()
                status = "Connected to signaling server"
                connected = true
            }
        }
        .navigationTitle("Between")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button() {
                    showHistory = true
                } label: {
                    Image(systemName: "clock")
                }
            }
            
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReset = true
                } label: {
                    Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                }
            }
        }
        .alert("Incoming Connection", isPresented: $webRTC.showConnectionAlert) {
            Button("Accept") {
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
            Text("\(webRTC.incomingConnectionPeerId ?? "Someone") is requesting to connect.")
        }
        .alert("New ID", isPresented: $showReset) {
            Button("Yes") {
                if deleteP256KeyAgreementPrivateKey(account: Config.appGroupIdentifier) {
                    
                    do {
                        try modelContext.delete(model: Message.self)
                        try modelContext.save()
                    } catch {
                        errorText = error.localizedDescription
                        status = ""
                        showError = true
                    }
                    
                    let key = loadP256KeyAgreementPrivateKey(account:Config.appGroupIdentifier)
                    if let publicKey = key?.publicKey {
                        pubKey = publicKey.rawRepresentation.base64EncodedString()
                        webRTC.localClientId = pubKey
                        webRTC.register()
                    }
                }
            }
            Button("No", role: .cancel) {
              
            }
        } message: {
            Text("Are you sure you want to get a new ID? This will delete all conversations and make you no longer reachable at your current ID.")
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                let uniqueConversations = messages
                    .sorted { $0.timestamp > $1.timestamp }
                    .reduce(into: [Message]()) { result, msg in
                        let peer = msg.from == webRTC.localClientId ? msg.to : msg.from
                        if !result.contains(where: { ($0.from == webRTC.localClientId ? $0.to : $0.from) == peer }) {
                            result.append(msg)
                        }
                    }
                
                if uniqueConversations.count > 0 {
                    
                    List(uniqueConversations) { msg in
                        let peer = msg.from == webRTC.localClientId ? msg.to : msg.from
                        let contact = contacts.first(where: { $0.webRTCId == peer })
                        NavigationLink(value: msg) {
                            HistoryRowView(peer: peer, contact: contact)
                        }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteMessages(from: peer)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .navigationDestination(for: Message.self) { msg in
                        let peer = msg.from == webRTC.localClientId ? msg.to : msg.from
                        ChatView(webRTC: webRTC, searchTarget: peer, searchTarget2: webRTC.localClientId, isViewingHistory: true)
                    }
                    .navigationTitle("Chat History")
                } else {
                    ContentUnavailableView {
                        Label("No chat history", systemImage: "clock.badge.xmar")
                    } description: {
                        Text("New chats you create will appear here.")
                    }
                }
            }
        }
    }
    
    private func deleteMessages(from peer: String) {
        let predicate = #Predicate<Message> { msg in
            msg.from == peer || msg.to == peer
        }
        try? modelContext.delete(model: Message.self, where: predicate)
        try? modelContext.save()
    }
}

struct HistoryRowView: View {
    let peer: String
    let contact: Contact?
    
    var body: some View {
        HStack {
            if let contact = contact,
               let imgData = contact.image,
               let uiImage = UIImage(data: imgData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .foregroundStyle(.gray)
            }
            Text(contact?.humanName ?? peer)
        }
    }
}

