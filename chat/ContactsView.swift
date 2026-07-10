import SwiftUI
import PhotosUI
import SwiftData
import MessageUI


struct ContactsView: View {
    
    @Environment(\.modelContext) var modelContext
    
    @State var searchQuery = ""
    
    @Query var contacts: [Contact]
    
    @State var showEdit = false
    
    @State var editing = ""
    
    @State var showBlocked = false
    
    private var filteredContacts: [Contact] {

        if searchQuery.isEmpty {

            return contacts

        }

        return contacts.filter {
            $0.humanName.localizedCaseInsensitiveContains(searchQuery)
        }

    }

    var body: some View {
        NavigationStack {
            List(filteredContacts) { contact in
                HistoryRowView(peer:contact.webRTCId, contact: contact, showId:true)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button() {
                            editing = contact.webRTCId
                            showEdit = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteContact(from: contact.webRTCId)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .navigationTitle("Contacts")
            .sheet(isPresented: $showEdit) {
                ContactEditView(contacts: contacts, searchTarget:$editing)
            }
            .sheet(isPresented:$showBlocked) {
                BlockedView()
            }
            .searchable(text: $searchQuery)
            .toolbar {
                Button() {
                    showBlocked = true
                } label: {
                    Image(systemName: "hand.raised")
                }
            }
        }
    }
    
    private func deleteContact(from peer: String) {
        let predicate = #Predicate<Contact> { c in
            c.webRTCId == peer
        }
        try? modelContext.delete(model: Contact.self, where: predicate)
        try? modelContext.save()
    }

    
}


struct ContactEditView: View {
    
    @Environment(\.modelContext) var modelContext
    
    @Environment(\.dismiss) var dismiss

    @State var renameText: String = ""
    @State private var contactImageItem: PhotosPickerItem?
    @State private var contactImageData: Data?
    
    @State private var previewImage: UIImage?
    @State private var showPreviewImage: Bool = false
    
    var contacts: [Contact]
    
    @Query var blockedUsers: [BlockedUser]
    
    var isBlocked: Bool {
        blockedUsers.first(where: { $0.webRTCid == searchTarget }) != nil
    }
    
    @Binding var searchTarget: String
    
    @State private var showMail = false
    @State private var mailResult: Result<MFMailComposeResult, Error>?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Info") {
                    ContactImagePickerRow(
                        contactImageItem: $contactImageItem,
                        contactImageData: $contactImageData
                    )
                    
                    Button("Remove Image") {
                        contactImageItem = nil
                        contactImageData = nil
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
                
                Section("Actions") {
                    Button {
                        if isBlocked {
                            try? modelContext.delete(
                                model: BlockedUser.self,
                                where: #Predicate { user in
                                    user.webRTCid == searchTarget
                                }
                            )
                            try? modelContext.save()
                        } else {
                            let u = BlockedUser(
                                webRTCid: searchTarget
                            )
                            modelContext.insert(u)
                        }
                    } label: {
                        Label( isBlocked ? "Unblock" : "Block", systemImage: "hand.raised")
                            .foregroundStyle(.red)
                    }
                    
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            showMail = true
                        } else {
                            let email = "report@coolstone.dev"
                            let subject = "Report User: \(searchTarget)"
                            let body = "Please describe the abusive behavior here. Because messages are encrypted and peer-to-peer, we cannot read your chat history. We recommend you also Block this user."
                            if let url = URL(string: "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                                UIApplication.shared.open(url)
                            }
                        }
                    } label: {
                        Label("Report", systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.orange)
                    }
                }
                
            }
            .sheet(isPresented: $showMail) {
                MailView(
                    result: $mailResult,
                    toRecipients: ["report@coolstone.dev"],
                    subject: "Report User: \(searchTarget)",
                    messageBody: "Please describe the abusive behavior here. Because messages are encrypted and peer-to-peer, we cannot read your chat history. We recommend you also Block this user."
                )
            }
            .navigationTitle("Contact")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear{
                if let existing = contacts.first(where: { $0.webRTCId == searchTarget }) {
                    renameText = existing.humanName
                    contactImageData = existing.image
                } else {
                    print("no existing for \(searchTarget)")
                    renameText = ""
                    contactImageData = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                       dismiss()
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
                        dismiss()
                    }
                }
            }
        }
    }
    
}

