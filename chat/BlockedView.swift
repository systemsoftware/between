import SwiftUI
import PhotosUI
import SwiftData


struct BlockedView: View {
    
    @Environment(\.modelContext) var modelContext
    
    @State var searchQuery = ""
    
    @Query var contacts: [BlockedUser]
    
    @State var showEdit = false
    
    @State var editing = ""
    

    var body: some View {
        NavigationStack {
            List(contacts) { contact in
                Text(contact.webRTCid)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteContact(from: contact.webRTCid)
                        } label: {
                            Label("Unblock", systemImage: "hand.raised.slash")
                        }
                    }
            }
            .navigationTitle("Blocked")
            .searchable(text: $searchQuery)
        }
    }
    
    private func deleteContact(from peer: String) {
        let predicate = #Predicate<BlockedUser> { c in
            c.webRTCid == peer
        }
        try? modelContext.delete(model: BlockedUser.self, where: predicate)
        try? modelContext.save()
    }

    
}
