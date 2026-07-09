import SwiftUI
import PhotosUI
import SwiftData


struct ContactsView: View {
    
    @Environment(\.modelContext) var modelContext
    
    @State var searchQuery = ""
    
    @Query var contacts: [Contact]
    
    @State var showEdit = false
    
    @State var editing = ""
    
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
            .searchable(text: $searchQuery)
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
    
    @Binding var searchTarget: String
    
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

