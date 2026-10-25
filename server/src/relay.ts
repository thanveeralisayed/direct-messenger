import { WebSocket } from 'ws';
import { WSClientFrame, WSServerFrame } from './types.js';

interface BufferedItem {
  packet: WSServerFrame;
  expiresAt: number;
}

/**
 * Ephemeral Relay Manager
 * Pure in-memory switching fabric. Never writes message content to disk.
 */
export class EphemeralRelay {
  // Active socket sessions by username
  private activeConnections: Map<string, WebSocket> = new Map();

  // In-memory buffer for offline peers (Max 24h TTL, zero disk persistence)
  private inMemoryQueue: Map<string, BufferedItem[]> = new Map();

  // 24 hours TTL in milliseconds
  private readonly BUFFER_TTL_MS = 24 * 60 * 60 * 1000;

  constructor() {
    // Periodic garbage collection for expired in-memory packets
    setInterval(() => this.pruneExpiredQueue(), 5 * 60 * 1000);
  }

  public registerConnection(username: string, socket: WebSocket): void {
    const user = username.toLowerCase();
    
    // Close existing connection if already open
    const existing = this.activeConnections.get(user);
    if (existing && existing !== socket && existing.readyState === WebSocket.OPEN) {
      existing.close(1000, 'Replaced by new connection');
    }

    this.activeConnections.set(user, socket);
    console.log(`[Relay] Connected: @${user} (Active: ${this.activeConnections.size})`);

    // Flush any pending in-memory packets
    this.flushQueue(user, socket);
  }

  public removeConnection(username: string, socket: WebSocket): void {
    const user = username.toLowerCase();
    if (this.activeConnections.get(user) === socket) {
      this.activeConnections.delete(user);
      console.log(`[Relay] Disconnected: @${user} (Active: ${this.activeConnections.size})`);
    }
  }

  public handleClientMessage(fromUser: string, rawData: string): void {
    const sender = fromUser.toLowerCase();
    let frame: WSClientFrame;
    try {
      frame = JSON.parse(rawData);
    } catch {
      this.sendToUser(sender, { type: 'error', message: 'Malformed JSON packet' });
      return;
    }

    switch (frame.type) {
      case 'ping': {
        this.sendToUser(sender, { type: 'pong' });
        break;
      }

      case 'message': {
        const recipient = frame.to.toLowerCase();
        const outgoing: WSServerFrame = {
          type: 'message',
          id: frame.id,
          from: sender,
          timestamp: frame.timestamp || Date.now(),
          ephemeralPublicKey: frame.ephemeralPublicKey,
          iv: frame.iv,
          ciphertext: frame.ciphertext,
          disappearingSeconds: frame.disappearingSeconds,
        };

        const recipientSocket = this.activeConnections.get(recipient);
        if (recipientSocket && recipientSocket.readyState === WebSocket.OPEN) {
          // Recipient is online: stream directly and discard
          recipientSocket.send(JSON.stringify(outgoing));
          this.sendToUser(sender, { type: 'server_ack', id: frame.id, status: 'relayed' });
          console.log(`[Relay] Instant relay: @${sender} -> @${recipient} (${frame.id})`);
        } else {
          // Recipient is offline: store temporarily in RAM buffer only
          this.bufferPacket(recipient, outgoing);
          this.sendToUser(sender, { type: 'server_ack', id: frame.id, status: 'buffered' });
          console.log(`[Relay] Buffered in RAM: @${sender} -> @${recipient} (${frame.id})`);
        }
        break;
      }

      case 'delivery_ack': {
        const originalSender = frame.sender.toLowerCase();
        const receipt: WSServerFrame = {
          type: 'delivery_receipt',
          id: frame.id,
          recipient: sender,
          timestamp: Date.now(),
        };
        this.sendToUser(originalSender, receipt);
        break;
      }

      case 'read_receipt': {
        const originalSender = frame.sender.toLowerCase();
        const receipt: WSServerFrame = {
          type: 'read_receipt',
          id: frame.id,
          recipient: sender,
          timestamp: Date.now(),
        };
        this.sendToUser(originalSender, receipt);
        break;
      }

      case 'typing': {
        const recipient = frame.to.toLowerCase();
        const indicator: WSServerFrame = {
          type: 'typing',
          from: sender,
          isTyping: frame.isTyping,
        };
        this.sendToUser(recipient, indicator);
        break;
      }

      default:
        break;
    }
  }

  private bufferPacket(recipient: string, packet: WSServerFrame): void {
    const queue = this.inMemoryQueue.get(recipient) || [];
    // Max 500 buffered packets per user to protect RAM
    if (queue.length > 500) {
      queue.shift(); // Drop oldest
    }
    queue.push({
      packet,
      expiresAt: Date.now() + this.BUFFER_TTL_MS,
    });
    this.inMemoryQueue.set(recipient, queue);
  }

  private flushQueue(username: string, socket: WebSocket): void {
    const queue = this.inMemoryQueue.get(username);
    if (!queue || queue.length === 0) return;

    console.log(`[Relay] Flushing ${queue.length} in-memory packets to @${username}`);
    const now = Date.now();
    for (const item of queue) {
      if (item.expiresAt > now && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify(item.packet));
      }
    }

    // Immediately clear from memory once delivered
    this.inMemoryQueue.delete(username);
  }

  private pruneExpiredQueue(): void {
    const now = Date.now();
    for (const [user, queue] of this.inMemoryQueue.entries()) {
      const valid = queue.filter(item => item.expiresAt > now);
      if (valid.length === 0) {
        this.inMemoryQueue.delete(user);
      } else {
        this.inMemoryQueue.set(user, valid);
      }
    }
  }

  public sendToUser(username: string, frame: WSServerFrame): boolean {
    const socket = this.activeConnections.get(username.toLowerCase());
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(frame));
      return true;
    }
    return false;
  }

  public isOnline(username: string): boolean {
    const socket = this.activeConnections.get(username.toLowerCase());
    return !!socket && socket.readyState === WebSocket.OPEN;
  }
}
