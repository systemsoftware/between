import Foundation
import WebRTC
internal import Combine

// MARK: - Delegate

protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManager(_ manager: WebRTCManager, didChangeConnectionState state: RTCIceConnectionState)
    func webRTCManagerDidConnectPeer(_ manager: WebRTCManager)
    func webRTCManagerDidDisconnect(_ manager: WebRTCManager)
}

/// Wire format used only between this client and the signaling server.
/// `type` is one of: "register", "offer", "answer", "candidate".
/// This never travels over the P2P data channel - only app-level `Event`s do.
private struct SignalingMessage: Codable {
    let type: String
    let from: String?
    let to: String?
    let sdp: String?
    let sdpMLineIndex: Int32?
    let sdpMid: String?

    init(type: String, from: String?, to: String?, sdp: String?, sdpMLineIndex: Int32?, sdpMid: String?) {
        self.type = type
        self.from = from
        self.to = to
        self.sdp = sdp
        self.sdpMLineIndex = sdpMLineIndex
        self.sdpMid = sdpMid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        sdp = try container.decodeIfPresent(String.self, forKey: .sdp)
        sdpMLineIndex = try container.decodeIfPresent(Int32.self, forKey: .sdpMLineIndex)
        sdpMid = try container.decodeIfPresent(String.self, forKey: .sdpMid)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(sdp, forKey: .sdp)
        try container.encodeIfPresent(sdpMLineIndex, forKey: .sdpMLineIndex)
        try container.encodeIfPresent(sdpMid, forKey: .sdpMid)
    }

    enum CodingKeys: String, CodingKey {
        case type, from, to, sdp, sdpMLineIndex, sdpMid
    }
}

/// Manages a single WebRTC peer connection.
///
/// Flow:
/// 1. `setSignalingServer(_:)` configures the relay (a plain WebSocket server that
///    forwards JSON messages based on their `to` field - see note at bottom of file).
/// 2. `connect(toUserId:)` opens the signaling socket, registers this client,
///    creates a data channel + offer, and sends the offer to `userId`.
/// 3. Offer/answer/candidate exchange happens over the signaling socket.
/// 4. As soon as the data channel (or ICE connection) reports `.open`/`.connected`,
///    the signaling socket is closed - from that point on everything is pure P2P.
/// 5. `send(_:)` pushes `Event`s directly over the data channel.
/// 6. `onMessage` fires for every `Event` received from the peer (e.g. `.incoming`,
///    `.send`, `.delete`) - i.e. everything that isn't connection plumbing.
final class WebRTCManager: NSObject, ObservableObject {

    // MARK: Public API

    weak var delegate: WebRTCManagerDelegate?

    /// Fired for every `Event` received from the connected peer over the data
    /// channel. Handshake messages (offer/answer/candidate) never reach here -
    /// they're consumed internally over the signaling socket.
    var onMessage: ((Event) -> Void)?

    @Published var showConnectionAlert = false
    @Published var incomingConnectionPeerId: String? = nil
    var connectionDecisionCallback: ((Bool) -> Void)? = nil

    var localClientId: String
    @Published private(set) var isPeerConnected = false
    @Published private(set) var isReadyToSend = false

    // MARK: Private - WebRTC

    /// Shared across every peer connection this process creates.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private let iceServers = ["stun:stun.l.google.com:19302"]
    
    var connectedTo = ""

    // MARK: Private - Signaling

    private var signalingURL: URL?
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var targetClientId: String?
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private var pendingEvents: [Event] = []
    private var pingTimer: Timer?

    // MARK: Init

    init(localClientId: String = UUID().uuidString) {
        self.localClientId = localClientId
        super.init()
    }

    // MARK: - Public API

    /// Configure (or reconfigure) the signaling server. Must be a ws:// or wss:// URL.
    /// Call this before `connect(toUserId:)`.
    func setSignalingServer(_ url: URL) {
        if signalingURL != url {
            closeSignalingSocket()
        }
        signalingURL = url
    }

    /// Connects to the signaling server and registers this client to receive incoming offers.
    func register() {
        guard let signalingURL = signalingURL else { return }
        if webSocketTask == nil {
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            guard signalingURL.scheme == "ws" || signalingURL.scheme == "wss" else { return }
            urlSession = session
            let task = session.webSocketTask(with: signalingURL)
            webSocketTask = task
            task.resume()
            startPingTimer()
            listenForSignalingMessages()
        }
        sendSignaling(SignalingMessage(type: "register", from: localClientId, to: nil, sdp: nil, sdpMLineIndex: nil, sdpMid: nil))
    }

    /// Initiates a P2P connection to `userId`.
    func connect(toUserId userId: String) {
        targetClientId = userId
        setupPeerConnection()
        setupOutgoingDataChannel()
        
        if webSocketTask == nil {
            register()
        }
        
        createOffer(to: userId)
    }

    /// Sends an `Event` to the connected peer over the (already P2P) data channel.
    /// If the channel is not open yet, the event is queued and sent when it opens.
    func send(_ event: Event) {
        guard let dataChannel = dataChannel, dataChannel.readyState == .open else {
            debugPrint("WebRTCManager: data channel not open yet, queuing event.")
            pendingEvents.append(event)
            return
        }
        guard let data = try? JSONEncoder().encode(event) else { return }
        dataChannel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    /// Tears down the peer connection, data channel, and signaling socket (if still open).
    func disconnect() {
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        closeSignalingSocket()
        DispatchQueue.main.async {
            self.isPeerConnected = false
            self.isReadyToSend = false
        }
        targetClientId = nil
        pendingRemoteCandidates.removeAll()
        pendingEvents.removeAll()
        delegate?.webRTCManagerDidDisconnect(self)
    }

    // MARK: - Peer connection / data channel setup

    private func setupPeerConnection() {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: iceServers)]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )
        peerConnection = WebRTCManager.factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    /// Only the side that initiates `connect(toUserId:)` creates the data channel;
    /// the answering side receives it via `peerConnection(_:didOpen:)`.
    private func setupOutgoingDataChannel() {
        let config = RTCDataChannelConfiguration()
        config.isOrdered = true
        dataChannel = peerConnection?.dataChannel(forLabel: "events", configuration: config)
        dataChannel?.delegate = self
    }

    // MARK: - Offer / Answer

    private func createOffer(to userId: String) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else {
                if let error = error { debugPrint("WebRTCManager: offer error \(error)") }
                return
            }
            self.peerConnection?.setLocalDescription(sdp) { _ in }
            self.sendSignaling(SignalingMessage(type: "offer", from: self.localClientId, to: userId, sdp: sdp.sdp, sdpMLineIndex: nil, sdpMid: nil))
        }
    }

    private func createAnswer(to userId: String) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection?.answer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else {
                if let error = error { debugPrint("WebRTCManager: answer error \(error)") }
                return
            }
            self.peerConnection?.setLocalDescription(sdp) { _ in }
            self.sendSignaling(SignalingMessage(type: "answer", from: self.localClientId, to: userId, sdp: sdp.sdp, sdpMLineIndex: nil, sdpMid: nil))
        }
    }

    // MARK: - Signaling I/O

    private func sendSignaling(_ message: SignalingMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                debugPrint("WebRTCManager: signaling send error \(error)")
            }
        }
    }

    private func listenForSignalingMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                debugPrint("WebRTCManager: signaling receive error \(error)")
                return // socket is gone (or was closed intentionally); stop looping

            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let signal = ( { let decoder = JSONDecoder(); return try? decoder.decode(SignalingMessage.self, from: data) } )() {
                    self.handleSignaling(signal)
                }
                self.listenForSignalingMessages() // keep listening while connected
            }
        }
    }

    private func handleSignaling(_ message: SignalingMessage) {
        switch message.type {
        case "offer":
            guard let sdp = message.sdp, let from = message.from else { return }
            
            // Ask the app layer if we should accept this connection
            DispatchQueue.main.async {
                self.incomingConnectionPeerId = from
                self.connectionDecisionCallback = { [weak self] accepted in
                    guard let self = self else { return }
                    if accepted {
                        self.acceptOffer(from: from, sdp: sdp)
                    } else {
                        debugPrint("WebRTCManager: Connection from \(from) rejected by user.")
                    }
                }
                self.showConnectionAlert = true
            }

        case "answer":
            guard let sdp = message.sdp else { return }
            let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdp)
            peerConnection?.setRemoteDescription(remoteSdp) { [weak self] _ in
                self?.drainPendingCandidates()
            }

        case "candidate":
            guard let sdp = message.sdp, let sdpMLineIndex = message.sdpMLineIndex else { return }
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: message.sdpMid)
            if peerConnection?.remoteDescription != nil {
                peerConnection?.add(candidate) { _ in }
            } else {
                pendingRemoteCandidates.append(candidate)
            }

        default:
            break
        }
    }

    private func acceptOffer(from: String, sdp: String) {
        targetClientId = from
        if peerConnection == nil {
            setupPeerConnection()
        }
        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
        peerConnection?.setRemoteDescription(remoteSdp) { [weak self] _ in
            self?.drainPendingCandidates()
            self?.createAnswer(to: from)
        }
    }

    private func drainPendingCandidates() {
        pendingRemoteCandidates.forEach { peerConnection?.add($0) { _ in } }
        pendingRemoteCandidates.removeAll()
    }

    private func closeSignalingSocket() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    debugPrint("WebRTCManager: ping error \(error)")
                }
            }
        }
    }

    /// Called the moment we detect a live P2P path - drops the signaling server.
    private func handlePeerBecameReachable() {
        guard !isPeerConnected else { return }
        DispatchQueue.main.async {
            self.isPeerConnected = true
        }
        closeSignalingSocket()
        delegate?.webRTCManagerDidConnectPeer(self)
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    private func updateReadyState() {
        DispatchQueue.main.async {
            let iceState = self.peerConnection?.iceConnectionState
            let isIceConnected = iceState == .connected || iceState == .completed
            let isDataOpen = self.dataChannel?.readyState == .open
            self.isReadyToSend = isIceConnected && isDataOpen
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        delegate?.webRTCManager(self, didChangeConnectionState: newState)

        switch newState {
        case .connected, .completed:
            handlePeerBecameReachable()
        case .failed, .closed:
            DispatchQueue.main.async {
                self.isPeerConnected = false
            }
        case .disconnected:
            // ICE disconnected can be temporary (e.g. network switch). Don't immediately boot the user out.
            break
        default:
            break
        }
        
        updateReadyState()
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let targetClientId = targetClientId else { return }
        sendSignaling(SignalingMessage(
            type: "candidate",
            from: localClientId,
            to: targetClientId,
            sdp: candidate.sdp,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdpMid: candidate.sdpMid
        ))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    /// The answering side receives its data channel here (the offering side
    /// already created its own in `setupOutgoingDataChannel()`).
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        updateReadyState()
        
        if dataChannel.readyState == .open {
            handlePeerBecameReachable()
            
            let queued = pendingEvents
            pendingEvents.removeAll()
            queued.forEach { send($0) }
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let event = try? JSONDecoder().decode(Event.self, from: buffer.data) else {
            debugPrint("WebRTCManager: received undecodable data channel message")
            return
        }
        // Everything that reaches the data channel is app-level (offer/answer/
        // candidate never travel here), so every event is forwarded to onMessage.
        onMessage?(event)
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebRTCManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        debugPrint("WebRTCManager: signaling socket opened")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        debugPrint("WebRTCManager: signaling socket closed (\(closeCode))")
    }
}

/*
 Expected signaling server contract (any simple WebSocket relay works):

 Client -> Server messages (JSON, matches `SignalingMessage` above):
   {"type":"register","from":"clientA"}
   {"type":"offer","from":"clientA","to":"clientB","sdp":"..."}
   {"type":"answer","from":"clientA","to":"clientB","sdp":"..."}
   {"type":"candidate","from":"clientA","to":"clientB","sdp":"...","sdpMLineIndex":0,"sdpMid":"0"}

 The server just needs to:
   1. Remember which socket registered as which `from` id.
   2. Forward every non-"register" message verbatim to the socket registered
      under the message's `to` id.

 No server-side WebRTC/media logic is required - it's a dumb relay used only
 until the two peers finish their ICE handshake and go direct.
*/

