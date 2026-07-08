import SwiftUI
import CryptoKit

struct ConnectView: View {
    
    @ObservedObject var webRTC: WebRTCManager
        
    @State private var pubKey: String = ""
    
    @State private var connectTo = ""
    
    // Connection Alert State
    @State private var showConnectionAlert = false
    @State private var pendingConnectionId: String? = nil
    @State var connectionDecisionCallback: ((Bool) -> Void)? = nil
    
    var body: some View {
        
        VStack {
            Text(pubKey)
                .onTapGesture {
                    UIPasteboard.general.string = pubKey
                }
            HStack {
                TextField("Connect to", text:$connectTo)
                Button("Connect") {
                    webRTC.connectedTo = connectTo
                    webRTC.connect(toUserId: connectTo)
                }
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

    }
}
