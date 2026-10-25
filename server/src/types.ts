/**
 * Wire Protocol and Types for Direct Ephemeral Relay Server & Flutter Client
 */

export interface UserRecord {
  username: string;
  passwordHash: string;
  salt: string;
  identityPublicKey: string; // Base64 Ed25519/X25519 public key
  createdAt: number;
}

// REST Payloads
export interface RegisterRequest {
  username: string;
  password: string; // Plaintext over TLS/local; hashed on arrival
  identityPublicKey: string; // Generated on device before registration
}

export interface LoginRequest {
  username: string;
  password: string;
}

export interface AuthResponse {
  token: string;
  username: string;
  identityPublicKey: string;
}

export interface UserPublicKeyResponse {
  username: string;
  identityPublicKey: string;
}

// WebSocket Protocol Frames
export type WSClientFrame =
  | { type: 'auth'; token: string }
  | {
      type: 'message';
      id: string; // UUID v4
      to: string; // Recipient username
      timestamp: number;
      ephemeralPublicKey: string; // Base64 X25519 key for ECDH
      iv: string; // Base64 12-byte IV for AES-256-GCM
      ciphertext: string; // Base64 ciphertext (E2EE)
    }
  | { type: 'delivery_ack'; id: string; sender: string }
  | { type: 'read_receipt'; id: string; sender: string }
  | { type: 'typing'; to: string; isTyping: boolean }
  | { type: 'ping' };

export type WSServerFrame =
  | { type: 'auth_success'; username: string }
  | { type: 'auth_error'; message: string }
  | {
      type: 'message';
      id: string;
      from: string;
      timestamp: number;
      ephemeralPublicKey: string;
      iv: string;
      ciphertext: string;
    }
  | { type: 'server_ack'; id: string; status: 'relayed' | 'buffered' }
  | { type: 'delivery_receipt'; id: string; recipient: string; timestamp: number }
  | { type: 'read_receipt'; id: string; recipient: string; timestamp: number }
  | { type: 'typing'; from: string; isTyping: boolean }
  | { type: 'pong' }
  | { type: 'error'; message: string };
