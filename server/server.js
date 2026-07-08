const WebSocket = require('ws');

const port = 3030;
const wss = new WebSocket.Server({ port, host: '0.0.0.0' }, () => {
  console.log(`Signaling server listening on ws://0.0.0.0:${port}`);
});

const clients = new Map();

wss.on('connection', (ws) => {
  console.log('New client connected.');

  ws.on('message', (message) => {
    try {
      const msg = JSON.parse(message);
      
      if (msg.type === 'register') {
        if (msg.from) {
          clients.set(msg.from, ws);
          console.log(`Registered client: ${msg.from}`);
        }
      } else {
        if (msg.to && clients.has(msg.to)) {
          const targetSocket = clients.get(msg.to);
          if (targetSocket.readyState === WebSocket.OPEN) {
            targetSocket.send(message.toString());
            console.log(`Forwarded ${msg.type} from ${msg.from} to ${msg.to}`);
          }
        } else {
          console.log(`Target client ${msg.to} not found for ${msg.type}.`);
        }
      }
    } catch (e) {
      console.error('Invalid message received:', message.toString());
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected.');
    for (const [id, socket] of clients.entries()) {
      if (socket === ws) {
        clients.delete(id);
        console.log(`Unregistered client: ${id}`);
        break;
      }
    }
  });
});
