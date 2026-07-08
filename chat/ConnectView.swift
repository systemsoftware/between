import SwiftUI
import CryptoKit
import SwiftData

struct ConnectView: View {
    
    @ObservedObject var webRTC: WebRTCManager
        
    @State private var pubKey: String = ""
    
    @State private var connectTo = ""
    
    @AppStorage("signalServer", store:Config.sharedDefaults) var signalServer = DEFAULT_SIGNAL_SERVER
    
    @State private var showConnectionAlert = false
    @State private var pendingConnectionId: String? = nil
    @State var connectionDecisionCallback: ((Bool) -> Void)? = nil
    
    @State var showHistory = false
    
    @Environment(\.modelContext) var modelContext
    @Query var messages: [Message]
    
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
                    Label("Signal Server", image:"server.rack")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Signal Server", text: $signalServer)
                        .textFieldStyle(.roundedBorder)
                }

                VStack{
                    Label("User ID", image:"person")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("User ID", text: $connectTo)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    webRTC.connectedTo = connectTo
                    webRTC.connect(toUserId: connectTo)
                } label: {
                    Label("Connect", systemImage: "arrow.right.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)

            }
            .padding(20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))

        }
        .padding()
        .animation(.smooth, value: connectTo)
        .onChange(of: signalServer) { _, s in
            if let url = URL(string:s) {
                webRTC.setSignalingServer(url)
            }
        }
        .onAppear {
            guard let url = URL(string:"ws://192.168.1.89:3030") else { print("Invalid URl"); return }
            webRTC.setSignalingServer(url)
            let key = loadP256KeyAgreementPrivateKey(account:Config.appGroupIdentifier)
            if let publicKey = key?.publicKey {
                pubKey = publicKey.rawRepresentation.base64EncodedString()
                webRTC.localClientId = pubKey
                webRTC.register()
                
                webRTC.incomingConnectionRequest = { peerId, completion in
                    DispatchQueue.main.async {
                        self.pendingConnectionId = peerId
                        self.connectionDecisionCallback = completion
                        self.showConnectionAlert = true
                    }
                }
            }
        }
        .toolbar {
            Button() {
                showHistory = true
            } label: {
                Image(systemName: "clock")
            }
        }
        .alert("Incoming Connection", isPresented: $showConnectionAlert) {
            Button("Accept") {
                connectionDecisionCallback?(true)
                webRTC.connectedTo = pendingConnectionId ?? ""
                connectionDecisionCallback = nil
                pendingConnectionId = nil
            }
            Button("Reject", role: .cancel) {
                connectionDecisionCallback?(false)
                connectionDecisionCallback = nil
                pendingConnectionId = nil
            }
        } message: {
            Text("\(pendingConnectionId ?? "Someone") is requesting to connect.")
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
                
                List(uniqueConversations) { msg in
                    let peer = msg.from == webRTC.localClientId ? msg.to : msg.from
                    NavigationLink(peer, value: msg)
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

