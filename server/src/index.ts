import Fastify from 'fastify';
import cors from '@fastify/cors';
import { WebSocketServer, WebSocket } from 'ws';
import crypto from 'node:crypto';
import { UserDatabase } from './db.js';
import { EphemeralRelay } from './relay.js';
import { RegisterRequest, LoginRequest } from './types.js';

const PORT = Number(process.env.PORT) || 8080;
const HOST = process.env.HOST || '0.0.0.0';

// Initialize core services
const db = new UserDatabase();
const relay = new EphemeralRelay();

// Active auth tokens (in-memory token store for MVP simplicity)
// Map<token, { username: string, expiresAt: number }>
const activeTokens = new Map<string, { username: string; expiresAt: number }>();

function generateToken(username: string): string {
  const token = crypto.randomBytes(32).toString('hex');
  // 30 days validity
  activeTokens.set(token, {
    username: username.toLowerCase(),
    expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000,
  });
  return token;
}

function verifyToken(token: string): string | null {
  const entry = activeTokens.get(token);
  if (!entry) return null;
  if (entry.expiresAt < Date.now()) {
    activeTokens.delete(token);
    return null;
  }
  return entry.username;
}

// Fastify application
const app = Fastify({ logger: true });

async function start() {
  await app.register(cors, {
    origin: '*',
  });

  // Root and Health checks
  app.get('/', async () => {
    return {
      status: 'ok',
      service: 'direct-ephemeral-relay',
      message: 'Direct Messenger Relay Server is active',
      timestamp: Date.now(),
    };
  });

  app.head('/', async (request, reply) => {
    reply.status(200).send();
  });

  app.get('/api/v1/health', async () => {
    return {
      status: 'ok',
      service: 'direct-ephemeral-relay',
      timestamp: Date.now(),
    };
  });

  // Register endpoint
  app.post<{ Body: RegisterRequest }>('/api/v1/auth/register', async (request, reply) => {
    const { username, password, identityPublicKey } = request.body || {};

    if (!username || !password || !identityPublicKey) {
      return reply.code(400).send({ error: 'Missing username, password, or identityPublicKey' });
    }

    try {
      const user = db.register(username, password, identityPublicKey);
      const token = generateToken(user.username);
      return reply.code(201).send({
        token,
        username: user.username,
        identityPublicKey: user.identityPublicKey,
      });
    } catch (err: any) {
      return reply.code(400).send({ error: err.message || 'Registration failed' });
    }
  });

  // Login endpoint
  app.post<{ Body: LoginRequest }>('/api/v1/auth/login', async (request, reply) => {
    const { username, password } = request.body || {};

    if (!username || !password) {
      return reply.code(400).send({ error: 'Missing username or password' });
    }

    const user = db.authenticate(username, password);
    if (!user) {
      return reply.code(401).send({ error: 'Invalid username or credentials' });
    }

    const { identityPublicKey } = request.body || {};
    if (identityPublicKey && typeof identityPublicKey === 'string' && identityPublicKey.length > 20 && identityPublicKey !== user.identityPublicKey) {
      db.updatePublicKey(user.username, identityPublicKey);
      user.identityPublicKey = identityPublicKey;
      console.log(`[Auth] Updated public key for user @${user.username} upon login`);
    }

    const token = generateToken(user.username);
    return reply.send({
      token,
      username: user.username,
      identityPublicKey: user.identityPublicKey,
    });
  });

  // Public Key Directory lookup
  app.get<{ Params: { username: string } }>('/api/v1/users/:username/key', async (request, reply) => {
    const username = request.params.username.toLowerCase();
    const key = db.getPublicKey(username);

    if (!key) {
      return reply.code(404).send({ error: 'User or public key not found' });
    }

    return reply.send({
      username,
      identityPublicKey: key,
      isOnline: relay.isOnline(username),
    });
  });

  // Bind server
  await app.listen({ port: PORT, host: HOST });
  console.log(`[HTTP] Direct Relay API listening on http://${HOST}:${PORT}`);

  // Attach WebSocket Server
  const wss = new WebSocketServer({ server: app.server, path: '/ws' });

  wss.on('connection', (socket: WebSocket, req) => {
    // Check if token was provided in query string: /ws?token=xyz
    const url = new URL(req.url || '', `http://${req.headers.host || 'localhost'}`);
    const queryToken = url.searchParams.get('token');

    let authenticatedUser: string | null = null;

    if (queryToken) {
      const user = verifyToken(queryToken);
      if (user) {
        authenticatedUser = user;
        relay.registerConnection(user, socket);
        socket.send(JSON.stringify({ type: 'auth_success', username: user }));
      } else {
        socket.send(JSON.stringify({ type: 'auth_error', message: 'Invalid or expired token' }));
        socket.close(4001, 'Unauthorized');
        return;
      }
    }

    socket.on('message', (data: Buffer | string) => {
      const raw = data.toString();

      // If not yet authenticated, require first frame to be auth
      if (!authenticatedUser) {
        try {
          const parsed = JSON.parse(raw);
          if (parsed.type === 'auth' && parsed.token) {
            const user = verifyToken(parsed.token);
            if (user) {
              authenticatedUser = user;
              relay.registerConnection(user, socket);
              socket.send(JSON.stringify({ type: 'auth_success', username: user }));
              return;
            }
          }
        } catch {
          // ignore error and reject
        }

        socket.send(JSON.stringify({ type: 'auth_error', message: 'Authentication required' }));
        socket.close(4001, 'Unauthorized');
        return;
      }

      // Route message through relay
      relay.handleClientMessage(authenticatedUser, raw);
    });

    socket.on('close', () => {
      if (authenticatedUser) {
        relay.removeConnection(authenticatedUser, socket);
      }
    });

    socket.on('error', (err) => {
      console.error(`[WebSocket Error] ${authenticatedUser || 'unauthed'}:`, err);
    });
  });
}

start().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
