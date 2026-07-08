import SwiftUI
import SwiftData


struct ContentView: View {
 
    @StateObject var webRTC = WebRTCManager()
    @Environment(\.modelContext) var modelContext
    
    @State var showWipeAlert = false
    
    var body: some View {
        if !webRTC.isPeerConnected {
            ConnectView(webRTC: webRTC)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ChatView(webRTC: webRTC, searchTarget: webRTC.connectedTo, searchTarget2: webRTC.localClientId)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture(count: 2) {
                  showWipeAlert = true
               }
            .alert("Are you sure you want to wipe all conversations?", isPresented: $showWipeAlert) {
                Button("Yes") {
                    Task {
                        do {
                            try modelContext.container.erase()
                        } catch {
                            print(error)
                        }
                    }
                }
                Button("No", role: .cancel) {
                    
                }
            }
        }
    }
    
}
