import SwiftUI
import CryptoKit
import SwiftData
import PhotosUI

struct ChatView: View {
    
    @ObservedObject var webRTC: WebRTCManager
        
    @State private var pubKey: String = ""
    
    @State private var text = ""
    @State private var selectedItem: PhotosPickerItem?
    
    @Environment(\.modelContext) private var modelContext
    
    @Query var messages: [Message]
    @Query var contacts: [Contact]
    
    @State var showRename = false
    @State var renameText: String = ""
    @State private var contactImageItem: PhotosPickerItem?
    @State private var contactImageData: Data?
    
    
    let searchTarget: String
    let searchTarget2: String
    
    var isViewingHistory = false
    
    init(webRTC: WebRTCManager, searchTarget: String, searchTarget2:String, isViewingHistory:Bool = false) {
        self.webRTC = webRTC
        self.searchTarget = searchTarget
        self.searchTarget2 = searchTarget2
        self.isViewingHistory = isViewingHistory
        
        let key = loadP256KeyAgreementPrivateKey(account:Config.appGroupIdentifier)
        let myPubKey = key?.publicKey.rawRepresentation.base64EncodedString() ?? ""
        
        _messages = Query(filter: #Predicate<Message> { msg in
            // Condition 1: searchTarget sent it to myPubKey
            (msg.from == searchTarget && msg.to == myPubKey) ||
            // Condition 2: myPubKey sent it to searchTarget
            (msg.from == myPubKey && msg.to == searchTarget)
        }, sort: \Message.timestamp)
        
    }

    
    var body: some View {
        
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messages) { msg in
                    let isMe = msg.from != searchTarget

                    VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                        if !isMe {
                            HStack {
                                Color.clear.frame(width: 30, height: 0)
                                Text(
                                    contacts.first(where: { $0.webRTCId == msg.from })?.humanName ?? ""
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }

                        HStack(alignment: .center) {
                            if isMe {
                                Spacer(minLength: 50)
                            } else {
                                if let contact = contacts.first(where: { $0.webRTCId == msg.from }),
                                   let imgData = contact.image,
                                   let uiImage = UIImage(data: imgData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())
                                        .foregroundStyle(.gray)
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(.gray)
                                }
                            }

                            if msg.content.hasPrefix("B64__IMAGE:"),
                               let base64String = msg.content.components(separatedBy: "B64__IMAGE:").last,
                               let data = Data(base64Encoded: base64String),
                               let uiImage = UIImage(data: data) {
                                
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            } else {
                                Text(msg.content)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        isMe
                                        ? Color.accentColor
                                        : Color.gray.opacity(0.2)
                                    )
                                    .foregroundStyle(isMe ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            }

                            if !isMe {
                                Spacer(minLength: 50)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .safeAreaInset(edge: .bottom) {
            if !isViewingHistory {
                HStack {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "photo")
                    }
                    
                    TextField("Message", text:$text)
                    Button() {
                        
                        let msg = Message(content: text, from: pubKey, to: searchTarget)
                        modelContext.insert(msg)
                        
                        if let enc = encryptP2PMessage(text, peerPublicKeyBase64: searchTarget) {
                            webRTC.send(Event(
                                type: .send, payload: enc
                            ))
                            
                            text = ""
                        } else {
                            print("Could not encrypt message")
                        }
                    } label:{
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(text.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                .glassEffect(in: .rect(cornerRadius: 16.0))
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showRename) {
            NavigationStack {
                Form {
                    Section("Info") {
                        HStack {
                            if let contactImageData, let uiImage = UIImage(data: contactImageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            PhotosPicker(selection: $contactImageItem, matching: .images) {
                                Text("Select Image")
                            }
                            .onChange(of: contactImageItem) { _, newValue in
                                Task {
                                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                        contactImageData = data
                                    }
                                }
                            }
                        }
                        
                        TextField("Name", text: $renameText)
                            .textInputAutocapitalization(.words)
                    }
                    
                    Section("ID") {
                        Text(searchTarget)
                        Button {
                            UIPasteboard.general.string = searchTarget
                        } label: {
                            Text("Copy ID")
                        }
                    }
                }
                .navigationTitle("Contact")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            renameText = ""
                            contactImageData = nil
                            contactImageItem = nil
                            showRename = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let existing = contacts.first(where: { $0.webRTCId == searchTarget }) {
                                existing.humanName = renameText
                                existing.image = contactImageData
                            } else {
                                let contact = Contact(
                                    webRTCid: searchTarget,
                                    humanName: renameText,
                                    image: contactImageData
                                )
                                modelContext.insert(contact)
                            }
                            try? modelContext.save()

                            renameText = ""
                            contactImageData = nil
                            contactImageItem = nil
                            showRename = false
                        }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .onAppear {
            let key = loadP256KeyAgreementPrivateKey(account:Config.appGroupIdentifier)
            if let publicKey = key?.publicKey {
                pubKey = publicKey.rawRepresentation.base64EncodedString()
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    
                    let maxSize: CGFloat = 300
                    let aspect = image.size.width / image.size.height
                    let newSize = aspect > 1 ? CGSize(width: maxSize, height: maxSize / aspect) : CGSize(width: maxSize * aspect, height: maxSize)
                    
                    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                    let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    if let jpegData = resizedImage?.jpegData(compressionQuality: 0.1) {
                        let base64 = jpegData.base64EncodedString()
                        let imagePayload = "B64__IMAGE:" + base64
                        
                        let msg = Message(content: imagePayload, from: pubKey, to: searchTarget)
                        modelContext.insert(msg)
                        
                        if let enc = encryptP2PMessage(imagePayload, peerPublicKeyBase64: searchTarget) {
                            webRTC.send(Event(type: .send, payload: enc))
                        } else {
                            print("Could not encrypt image message")
                        }
                    }
                    
                    selectedItem = nil
                }
            }
        }
        .navigationTitle(
            contacts.first(where: { $0.webRTCId == searchTarget })?.humanName
                ?? searchTarget
        )
        .navigationSubtitle(searchTarget)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button() {
                if let existing = contacts.first(where: { $0.webRTCId == searchTarget }) {
                    renameText = existing.humanName
                    contactImageData = existing.image
                } else {
                    renameText = ""
                    contactImageData = nil
                }
                showRename = true
            } label: {
                Image(systemName: "pencil")
            }
            
            
            if !isViewingHistory {
                Button {
                    webRTC.disconnect()
                    webRTC.connectedTo = ""
                } label: {
                    Image(systemName:"rectangle.portrait.and.arrow.forward")
                }
            }
            
        }
    }
}
