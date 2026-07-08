# Between

An end-to-end encrypted, peer-to-peer chat application built with **SwiftUI** and **WebRTC**. 

This repository contains both the iOS client application and a lightweight Node.js signaling server used for the initial peer discovery. Once peers are connected, the signaling server is dropped and all communication happens directly over a secure WebRTC data channel.

## Features

- **Peer-to-Peer Communication:** Direct connection between clients via WebRTC data channels.
- **End-to-End Encryption:** Messages are encrypted before being sent over the peer-to-peer network.
- **Decentralized Signaling:** A minimal Node.js WebSocket server is used strictly for the initial WebRTC handshake (SDP offers/answers and ICE candidates). 
- **Local Persistence:** Chat history and contacts are saved locally on your device using **SwiftData**.
- **Modern UI:** Built entirely with SwiftUI.

## Architecture

- **Client (`chat/`):** A Swift iOS app. Uses `RTCPeerConnection` for establishing the direct link and `RTCDataChannel` for messaging. 
- **Signaling Server (`server/`):** A lightweight WebSocket server (`server.js`) that forwards WebRTC handshake messages (`register`, `offer`, `answer`, `candidate`). It does not handle, see, or store the actual chat messages.

## Prerequisites

- **iOS Client:**
  - Xcode 15 or later
  - iOS 17.0+ device or simulator
  
- **Signaling Server:**
  - Node.js (v14 or later)
  - npm

## Getting Started

### 1. Run the Signaling Server

Navigate to the server directory, install dependencies, and start the server:

```bash
cd server
npm install
npm start
```

The signaling server will start listening on `ws://0.0.0.0:3030`. 

> **Note:** For physical iOS devices to connect, ensure your iPhone is on the same local network as your Mac, and configure the app to connect to your Mac's local IP address (e.g., `192.168.1.x`) rather than `localhost`.

### 2. Run the iOS App

1. Open `chat.xcodeproj` in Xcode.
2. Select your target device or simulator.
3. Build and run the app.
4. On the connect screen, you can connect to another peer by entering their connection ID (or they can connect to you). Ensure you have configured the signaling server URL appropriately in the app.

## How It Works (WebRTC Flow)

1. **Registration:** When the app launches, it connects to the signaling server and registers its local client ID.
2. **Handshake:** When connecting to a peer, the app generates a WebRTC offer and sends it through the signaling server to the target client. The target replies with an answer, and both exchange ICE candidates to discover the optimal network path.
3. **P2P Connection:** Once the `RTCDataChannel` opens, the app disconnects from the signaling server. 
4. **Messaging:** All subsequent messages (e.g., chat messages, typing indicators) are encrypted and sent directly over the P2P connection, bypassing any central server.

## Data Management

All data is stored locally using **SwiftData**. 
- To wipe the local database (messages or contacts), you can double-tap the main chat view to bring up the data management alert.

## License

MIT License
