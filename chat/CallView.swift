import SwiftUI
import SwiftData
internal import Combine

struct CallView: View {
    
    @ObservedObject var webRTC: WebRTCManager
    @State var searchTarget: String
    @Query var contacts: [Contact]
    
    @State private var isMuted = false
    
    @State private var startTime = Date()
    @State private var timeElapsed: Double = 0
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var contact: Contact? {
        contacts.first(where: { $0.webRTCId == searchTarget })
    }
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            if let contact = contact, let imgData = contact.image, let uiImage = UIImage(data: imgData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 150, height: 150)
                    .foregroundColor(.gray)
            }
            
            Text(contact?.humanName ?? searchTarget)
                .font(.title)
                .bold()
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal)
            
            Text(Duration.seconds(timeElapsed), format: .time(pattern: .hourMinuteSecond))
                .monospacedDigit()
                .font(.subheadline)
                .foregroundColor(.green)
            
            Spacer()
            
            HStack(spacing: 60) {
                Button {
                    isMuted.toggle()
                    webRTC.setAudioEnabled(!isMuted)
                } label: {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title)
                        .padding()
                        .background(isMuted ? Color.red.opacity(0.8) : Color.gray.opacity(0.2))
                        .foregroundColor(isMuted ? .white : .primary)
                        .clipShape(Circle())
                }
                
                Button {
                    let event = Event(type: .endCall, payload: "")
                    webRTC.send(event)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        webRTC.disconnect()
                        webRTC.connectedTo = ""
                    }
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .padding(24)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
            .padding(.bottom, 40)
        }
        .onReceive(timer) { _ in
                  timeElapsed = Date().timeIntervalSince(startTime)
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
    }
}
