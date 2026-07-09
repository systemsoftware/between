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
    
    @State private var previewImage: UIImage?
    @State private var showPreviewImage: Bool = false
    
    @State var searchTarget: String
    let searchTarget2: String
    
    var isViewingHistory = false
    
    @State var replyingTo: UUID? = nil
    
    @State var showRename = false
    
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
                    MessageRowView(
                        msg: msg,
                        searchTarget: searchTarget,
                        contacts: contacts,
                        previewImage: $previewImage,
                        showPreviewImage: $showPreviewImage,
                        replyingTo: $replyingTo,
                        webRTC:webRTC,
                        replyingToText:messages.first(where: { $0.event == msg.replyingTo })?.content ?? ""
                    )
                }
            }
            .padding(.vertical)
        }
        .safeAreaInset(edge: .bottom) {
            if !isViewingHistory {
                VStack {
                    
                    if let replyID = replyingTo {
                        HStack {
                            if let msg = messages.first(where: { $0.event == replyID }) {
                                Text("Replying to: \(msg.content.hasPrefix("B64__IMAGE:") ? "Image" : msg.content)")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text("Replying to message")
                            }
                            Spacer()
                            Button {
                                replyingTo = nil
                            } label: {
                                Image(systemName:"xmark")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.gray)
                        
                    }
                    
                    if webRTC.isReadyToSend {
                        HStack {
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Image(systemName: "photo")
                            }
                            
                            TextField("Message", text:$text)
                            Button() {
                                
                                
                                if let enc = encryptP2PMessage(text, peerPublicKeyBase64: searchTarget) {
                                    
                                    
                                    let event = Event(
                                        type: .send, payload: enc,
                                        replyingTo: replyingTo?.uuidString
                                    )
                                    
                                    let msg = Message(content: text, from: pubKey, to: searchTarget, event:event.id, replyingTo:replyingTo)
                                    modelContext.insert(msg)
                                    
                                    webRTC.send(event)
                                    
                                    text = ""
                                    
                                    replyingTo = nil
                                    
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
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showPreviewImage) {
            if let img = previewImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
        }.onChange(of: showPreviewImage) { _, n in
            if !n {
                previewImage = nil
            }
        }
        .sheet(isPresented: $showRename) {
            ContactEditView(contacts: contacts, searchTarget:$searchTarget)
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
                        
                      
                        
                        if let enc = encryptP2PMessage(imagePayload, peerPublicKeyBase64: searchTarget) {
                            let event = Event(type: .send, payload: enc)
                            let msg = Message(content: imagePayload, from: pubKey, to: searchTarget, event:event.id, replyingTo:replyingTo)
                            modelContext.insert(msg)
                            webRTC.send(event)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button() {
                    showRename = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
            
            
            if !isViewingHistory {
                ToolbarItem(placement: .topBarTrailing) {
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
}

struct MessageRowView: View {
    let msg: Message
    let searchTarget: String
    let contacts: [Contact]
    @Binding var previewImage: UIImage?
    @Binding var showPreviewImage: Bool
    
    @Binding var replyingTo: UUID?
    
    @Environment(\.modelContext) var modelContext
    
    var webRTC: WebRTCManager

    var contact: Contact? {
        contacts.first(where: { $0.webRTCId == msg.from })
    }

    var isMe: Bool {
        msg.from != searchTarget
    }

    var replyingToText: String = ""
    
    var body: some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                HStack {
                    if !isMe {
                    Text(
                        contact?.humanName ?? ""
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                    }
                    
                    
                    if !replyingToText.isEmpty {
                        Label(replyingToText.hasPrefix("B64__IMAGE:") ? "Image" : replyingToText, systemImage: "arrowshape.turn.up.left.fill")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
            }

            HStack(alignment: .center) {
                if isMe {
                    Spacer(minLength: 50)
                } else {
                    if let contact = contact,
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
                        .onTapGesture {
                            previewImage = uiImage
                            showPreviewImage = true
                        }
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
        .contextMenu {
         
            if webRTC.isPeerConnected {
                Button("Reply") {
                    replyingTo = msg.event
                }
                
                Divider()
            }
            
            if msg.from == webRTC.localClientId {
                if webRTC.isPeerConnected {
                    Button("Unsend") {
                        let event = Event(
                            type:.delete,
                            payload: msg.event?.uuidString ?? ""
                        )
                        
                        webRTC.send(event)
                        
                        do {
                            modelContext.delete(msg)
                            try modelContext.save()
                        } catch {
                            print("Failed to delete: \(error)")
                        }
                    }
                }
            }
            Button("Delete for You") {
                do {
                    modelContext.delete(msg)
                    try modelContext.save()
                } catch {
                    print("Failed to delete: \(error)")
                }
            }
            
        }
    }
}


struct ContactImagePickerRow: View {
    @Binding var contactImageItem: PhotosPickerItem?
    @Binding var contactImageData: Data?
    
    var body: some View {
            HStack {
                if let data = contactImageData, let uiImage = UIImage(data: data) {
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
                    guard newValue != nil else { return }
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            contactImageData = data
                        }
                    }
                }
            }
    }
}
