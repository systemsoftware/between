import SwiftUI
import SwiftData


struct HistoryView: View {
 
    @StateObject var webRTC: WebRTCManager
    @Environment(\.modelContext) var modelContext
    
    @Query var messages: [Message]
    
    @Query var contacts: [Contact]
    
    
    @State var searchQuery = ""
    
    private var filteredMessages: [Message] {

        if searchQuery.isEmpty {

            return messages

        }

        return messages.filter {
            $0.content.localizedCaseInsensitiveContains(searchQuery)
        }

    }
    
    var body: some View {
        NavigationStack {
            let uniqueConversations = filteredMessages
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
                    Label("No chat history", systemImage: "clock.badge.xmark")
                } 
            }
        }
        .searchable(text: $searchQuery)
    }
    
    
    
    private func deleteMessages(from peer: String) {
        let predicate = #Predicate<Message> { msg in
            msg.from == peer || msg.to == peer
        }
        try? modelContext.delete(model: Message.self, where: predicate)
        try? modelContext.save()
    }

    
}
