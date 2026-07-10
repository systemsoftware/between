# Signaling Server

A simple Node.js WebSocket signaling server for peer-to-peer communication (e.g., WebRTC). It acts as a message relay between connected clients.

## Features

- **WebSocket Communication:** Uses the `ws` library for fast, real-time communication.
- **Client Registration:** Clients register with a unique identifier (`from`).
- **Message Forwarding:** Forwards messages directly to the intended recipient using their identifier (`to`).
- **Connection Management:** Automatically pings clients every 30 seconds and terminates dead connections to free up resources.
- **HTTP Health Check:** Provides a basic HTTP endpoint to verify the server is running.

## Prerequisites

- Node.js installed on your machine.

## Installation

1. Navigate to the server directory:
   ```bash
   cd server
   ```
2. Install the dependencies:
   ```bash
   npm install
   ```

## Usage

Start the server:

```bash
npm start [port]
```

The server will start listening on all network interfaces (`0.0.0.0`) on port **3030**. 
The HTTP health check is available at `http://localhost:3030/`.
WebSocket connections should be made to `ws://localhost:3030/`.

## Protocol

Clients communicate with the server using JSON-formatted messages.

### 1. Registration

When a client connects, it must register itself to receive messages.

```json
{
  "type": "register",
  "from": "your_unique_client_id"
}
```

### 2. Sending Messages

To send a message to another connected client, include the `to` field with their unique ID. The server will forward the entire JSON payload to the target client.

```json
{
  "type": "any_custom_type",
  "from": "your_unique_client_id",
  "to": "target_client_id",
  "data": {
    "key": "value"
  }
}
```

If the target client is connected, they will receive the exact message. If the target client is not found, the server will log that the target was not found.
