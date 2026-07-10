const WebSocket = require('ws');
const http = require('http');

const server = http.createServer();

const port = process.argv[2] || 3030;
const wss = new WebSocket.Server({ server });

const LOG = process.argv.includes('--log');

const clients = new Map();

server.on('request', (req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Signal Server is running\n');
});

wss.on('connection', (ws) => {

    ws.isAlive = true;

  ws.on('pong', () => {

    ws.isAlive = true;

  });

  if (LOG) {
    console.log('New client connected.');
  }

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
            if (LOG) {
              console.log(`Forwarded ${msg.type} from ${msg.from} to ${msg.to}`);
            }
          }
        } else {
          if (LOG) {
            console.log(`Target client ${msg.to} not found for ${msg.type}.`);
          }
        }
      }
    } catch (e) {
      console.error('Invalid message received:', message.toString());
    }
  });

  ws.on('close', () => {
    if (LOG) {
      console.log('Client disconnected.');
    }
    for (const [id, socket] of clients.entries()) {
      if (socket === ws) {
        clients.delete(id);
        if (LOG) {
          console.log(`Unregistered client: ${id}`);
        }
        break;
      }
    }
  });
});


server.listen(port, "0.0.0.0", () => {
  console.log(`Signaling server listening on :${port}`);
});

const interval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      console.log("Terminating dead client");
      return ws.terminate();
    }

    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => {
  clearInterval(interval);
});