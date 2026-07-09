import SwiftUI
import CryptoKit
import SwiftData
import UIKit

struct ConnectView: View {
    
    @ObservedObject var webRTC: WebRTCManager
    
    @Environment(\.modelContext) var modelContext
        
    @State private var pubKey: String = ""
    
    @State private var connectTo = ""
    
    @AppStorage("signalServer", store:Config.sharedDefaults) var signalServer = DEFAULT_SIGNAL_SERVER
    
    @State var showReset = false
    
    @State var showError = false
    @State var errorText = ""
    
    @State var status = ""
    
    @State var connected = false
    
    @Query var contacts: [Contact]
    
    private var incomingConnectionName: String {
        contacts.first(where: { $0.webRTCId == webRTC.incomingConnectionPeerId })?.humanName
            ?? webRTC.incomingConnectionPeerId
            ?? "Someone"
    }
        
    var body: some View {
            
        VStack(spacing: 24) {
            // Public Key
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        showReset = true
                    }
                    .font(.caption)
                }

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
                            showError = false
                            if let url = URL(string:signalServer) {
                                status = "Setting signaling server"
                                webRTC.setSignalingServer(url)
                                status = "Pinging signaling server"
                                Task {
                                    let pong = await ping(url)
                                    
                                    if pong {
                                        status = "Registering with signaling server"
                                        webRTC.register()
                                        status = "Connected to signaling server"
                                        connected = true
                                    } else {
                                        status = "Signaling server not reachable"
                                        showError = true
                                    }
                                }
                            } else {
                                status = "Invalid URL"
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
                                    status = "Signaling server not reachable"
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

                
            }
            .padding(20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
            Spacer()
        }
        .padding()
        .animation(.smooth, value: connectTo)
        .safeAreaInset(edge: .bottom) {
            if !status.isEmpty {
                HStack {
                    if !connected && !showError {
                        ProgressView()
                    } else if showError {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text(status)
                }
                .padding()
                .glassEffect(.regular.interactive())
                .frame(maxWidth:.infinity)
            }
        }
        .onAppear {
            Task {
                guard let url = URL(string:signalServer) else {
                    errorText = "Invalid URL"
                    status = "Invalid URL"
                    showError = true
                    return
                }
                
                status = "Setting signaling server"
                webRTC.setSignalingServer(url)
                status = "Pinging signaling server"
                
                let key = loadP256KeyAgreementPrivateKey(account:Config.appGroupIdentifier)
                if let publicKey = key?.publicKey {
                    pubKey = publicKey.rawRepresentation.base64EncodedString()
                    webRTC.localClientId = pubKey
                    let pong = await ping(url)

                    if pong {
                        status = "Registering with signaling server"
                        webRTC.register()
                        status = "Connected to signaling server"
                        connected = true
                    } else {
                        showError = true
                        status = "Signaling server not reachable"
                    }
                }
            }
        }
        .navigationTitle("Between")
        .navigationBarTitleDisplayMode(.inline)
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
            Text("\(incomingConnectionName) is requesting to connect.")
        }
        .alert("New ID", isPresented: $showReset) {
            Button("Yes") {
                if deleteP256KeyAgreementPrivateKey(account: Config.appGroupIdentifier) {
                    
                    do {
                        try modelContext.delete(model: Message.self)
                        try modelContext.save()
                    } catch {
                        status = error.localizedDescription
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
    }

}

struct HistoryRowView: View {
    let peer: String
    let contact: Contact?
    
    var showId = false
    
    @State var showCopiedAlert = false
    
    
      private var copyTap: (some Gesture)? {
          showId ? TapGesture().onEnded {
              UIPasteboard.general.string = peer
              showCopiedAlert = true
          } : nil
      }
    
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
           
            VStack(alignment: .leading) {
                Text(contact?.humanName ?? peer)
                
                if showId && contact?.humanName != nil {
                    Text(peer)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            
        }
        .gesture(copyTap)
        .alert("Copied",isPresented: $showCopiedAlert) {
            Button("Ok",role:.cancel) {
                
            }
        } message: {
            Text("Copied contact's ID to clipboard")
        }
    }
}

