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
    
    @Query var blockedUsers: [BlockedUser]
    
    @Binding var tab: String
    
    @State var showHelp = false
    
    @Environment(\.openURL) private var openURL

    @State private var copiedTrigger = false
    @State private var didCopy = false

    
    private var incomingConnectionName: String {
        contacts.first(where: { $0.webRTCId == webRTC.incomingConnectionPeerId })?.humanName
            ?? webRTC.incomingConnectionPeerId
            ?? "Someone"
    }
        
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                identityCard
                connectionCard
            }
            .padding()
        }

        .fontDesign(.rounded)
        .tint(.blue)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: connectTo)
        .safeAreaInset(edge: .bottom) {
            statusBanner
        }
        .onChange(of: webRTC.connectionError) { _, newError in
            if let error = newError {
                status = error
                showError = true
                connected = false
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
                    let basePubKey = publicKey.rawRepresentation.base64EncodedString()
                    pubKey = basePubKey
                    webRTC.localClientId = basePubKey
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
        .toolbar {
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
        }
        .alert("Info", isPresented: $showHelp) {
            Button("Source Code") {
                let url = URL(string:"https://github.com/systemsoftware/between/")
                openURL(url!)
            }
            Button("Privacy Policy") {
                let url = URL(string:"https://github.com/systemsoftware/between/blob/main/PrivacyPolicy.md")
                openURL(url!)
            }
            Button("EULA") {
                let url = URL(string:"https://github.com/systemsoftware/between/blob/main/EULA.md")
                openURL(url!)
            }
            Button("Close") {
                showHelp = false
            }
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
                        let basePubKey = publicKey.rawRepresentation.base64EncodedString()
                        pubKey = basePubKey
                        webRTC.localClientId = basePubKey
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

    // MARK: - Identity Card

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionIcon("person.text.rectangle.fill", tint: .blue)
                Text("Your Identity")
                    .font(.headline)
                Spacer()
                Button("Reset", role: .destructive) {
                    showReset = true
                }
                .font(.subheadline.weight(.medium))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PUBLIC KEY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Text(pubKey.isEmpty ? "Generating…" : pubKey)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                ZStack {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .opacity(didCopy ? 0 : 1)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .opacity(didCopy ? 1 : 0)
                }
                .font(.title3)
                .animation(.easeInOut(duration: 0.2), value: didCopy)
            }
            .padding(14)
    //        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .sensoryFeedback(.success, trigger: copiedTrigger)
            .onTapGesture {
                didCopy = true
                copiedTrigger.toggle()
                UIPasteboard.general.string = pubKey

                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        didCopy = false
                    }
                }
            }
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 20) {

            fieldGroup(icon: "server.rack", title: "Signaling Server") {
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
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(.blue.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            fieldGroup(icon: "person.circle.fill", title: "Target User ID") {
                TextField("User ID", text: $connectTo)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Connection Type", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                Picker("Connection Type", selection: $webRTC.enableAudio) {
                    Text("Text Chat").tag(false)
                    Text("Voice Call").tag(true)
                }
                .pickerStyle(.segmented)
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
                            showError = false
                            connected = false
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
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if !status.isEmpty {
            HStack(spacing: 10) {
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
                    .font(.subheadline)
            }
            .padding()
            .glassEffect(.regular.interactive())
            .frame(maxWidth:.infinity)
            .padding(.horizontal)
        }
    }

    // MARK: - Shared building blocks

    private func sectionIcon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .foregroundStyle(tint)
            .font(.subheadline.weight(.semibold))
    }

    private func fieldGroup<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            content()
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
        HStack(spacing: 12) {
            Group {
                if let contact = contact,
                   let imgData = contact.image,
                   let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(contact?.humanName ?? peer)
                    .font(.body)

                if showId && contact?.humanName != nil {
                    Text(peer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .gesture(copyTap)
        .alert("Copied", isPresented: $showCopiedAlert) {
            Button("Ok", role: .cancel) {

            }
        } message: {
            Text("Copied contact's ID to clipboard")
        }
    }
}
