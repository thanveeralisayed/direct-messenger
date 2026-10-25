# Direct 🔒

**Direct** is a lightweight, privacy-focused Flutter Android chat application built with a **zero-knowledge, zero-storage** architecture.

Messages are end-to-end encrypted on the sender's device and decrypted only on the recipient's device. The backend relay server acts purely as an ephemeral switching switch—it **never stores any chat messages, media, or conversation history on disk**.

---

## Architecture Overview

```
+-------------------+                          +-------------------+
|   Alice (App)     |                          |    Bob (App)      |
|                   |                          |                   |
| 1. Generates      |                          | 1. Generates      |
|    X25519 Keypair |                          |    X25519 Keypair |
| 2. Encrypts with  |                          | 2. Decrypts with  |
|    AES-256-GCM    |                          |    Private Key    |
| 3. Stores in      |                          | 3. Stores in      |
|    Local SQLite   |                          |    Local SQLite   |
+---------+---------+                          +---------^---------+
          |                                              |
          | Encrypted Packet                             | Encrypted Packet
          v                                              |
   +-------------------------------------------------------------+
   |                  Direct Ephemeral Relay                     |
   |                                                             |
   |  • User Directory: Usernames & Identity Public Keys only    |
   |  • In-Memory WebSocket Routing:                             |
   |      - If peer is online: forward packet and drop from RAM  |
   |      - If peer is offline: temporary RAM buffer (max 24h)   |
   |  • ZERO DISK WRITES FOR CHATS OR LOGS                      |
   +-------------------------------------------------------------+
```

---

## Repository Structure

```
direct/
├── app/                  # Flutter Android Client Application
│   ├── android/          # Android platform configuration & permissions
│   ├── lib/
│   │   ├── core/
│   │   │   ├── crypto/   # X25519 & AES-256-GCM E2EE Crypto Engine & Keystore
│   │   │   ├── database/ # Local SQLite encrypted database (messages & contacts)
│   │   │   ├── models/   # Message and Contact models
│   │   │   └── network/  # WebSocket Relay & REST API Client
│   │   ├── providers/    # AuthProvider & ChatProvider state management
│   │   ├── ui/           # Modern Dark Theme, Screens, & Dialogs
│   │   └── main.dart
│   └── test/             # Cryptographic & widget test suites
│
└── server/               # Minimal Ephemeral Relay & Directory Server
    ├── src/
    │   ├── db.ts         # User registry (usernames and public keys only)
    │   ├── relay.ts      # Pure in-memory switching fabric & TTL buffer
    │   ├── types.ts      # Wire protocol & WebSocket packet schemas
    │   └── index.ts      # Fastify server & WebSocket handler
    └── test_smoke.mjs    # Automated end-to-end integration test
```

---

## Quickstart Guide

### 1. Start the Relay Server

```bash
cd server
npm install
npm run build
npm start
```
The server will bind to `http://0.0.0.0:8080` with WebSocket endpoint `ws://localhost:8080/ws`.

To run the automated smoke test:
```bash
node test_smoke.mjs
```

### 2. Run the Flutter Android App

```bash
cd app
flutter pub get
flutter run
```

#### Connecting to the Relay:
- **Android Emulator**: In the app's settings dialog (gear icon on login screen), the default server is `http://10.0.2.2:8080`.
- **Physical Android Phone**: Enter your computer's local Wi-Fi IP address (e.g., `http://192.168.1.150:8080`).
- **Windows Desktop / Web**: Use `http://localhost:8080`.

---

## Security & Privacy Primitives

* **Key Exchange**: X25519 Elliptic Curve Diffie-Hellman (ECDH).
* **Payload Encryption**: AES-256-GCM authenticated cipher with unique 12-byte initialization vectors per message.
* **Forward Secrecy**: An ephemeral one-time keypair is generated for every outgoing message packet.
* **Safety Numbers**: 24-character hexadecimal fingerprint grouped in blocks with QR code generation for in-person out-of-band verification.
* **Local Data Sovereignty**: All chat history and contacts are stored in the device's local database. Tapping **"Wipe Device Data"** permanently deletes all keys and local databases.
