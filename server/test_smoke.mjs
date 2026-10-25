import http from 'node:http';
import { WebSocket } from 'ws';

const BASE_URL = 'http://localhost:8080';
const WS_URL = 'ws://localhost:8080/ws';

async function request(path, options = {}) {
  const url = `${BASE_URL}${path}`;
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    ...options,
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}: ${JSON.stringify(data)}`);
  }
  return data;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function run() {
  console.log('--- Direct Server Automated Smoke Test ---');

  // 1. Health check
  console.log('1. Checking health endpoint...');
  const health = await request('/api/v1/health');
  console.log('   Health response:', health);

  // 2. Register Alice and Bob
  console.log('2. Registering Alice and Bob...');
  const aliceReg = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      username: 'alice',
      password: 'alicepassword123',
      identityPublicKey: 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA-alice-public-key',
    }),
  });
  console.log('   Alice registered:', aliceReg.username, 'Token:', aliceReg.token.slice(0, 8) + '...');

  const bobReg = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      username: 'bob',
      password: 'bobpassword123',
      identityPublicKey: 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA-bob-public-key',
    }),
  });
  console.log('   Bob registered:', bobReg.username, 'Token:', bobReg.token.slice(0, 8) + '...');

  // 3. Key Directory Lookup
  console.log('3. Looking up Bob public key...');
  const bobKeyLookup = await request('/api/v1/users/bob/key');
  console.log('   Found Bob key:', bobKeyLookup.identityPublicKey.slice(0, 30) + '...');

  // 4. WebSocket connection for Alice
  console.log('4. Connecting Alice over WebSocket...');
  const aliceWs = new WebSocket(`${WS_URL}?token=${aliceReg.token}`);
  await new Promise((res, rej) => {
    aliceWs.on('open', res);
    aliceWs.on('error', rej);
  });
  console.log('   Alice connected!');

  // 5. WebSocket connection for Bob
  console.log('5. Connecting Bob over WebSocket...');
  const bobWs = new WebSocket(`${WS_URL}?token=${bobReg.token}`);
  await new Promise((res, rej) => {
    bobWs.on('open', res);
    bobWs.on('error', rej);
  });
  console.log('   Bob connected!');

  // Setup Bob listener
  const bobReceivedPromise = new Promise((resolve) => {
    bobWs.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'message') {
        console.log('   [Bob received]:', msg);
        // Bob returns delivery ACK
        bobWs.send(JSON.stringify({
          type: 'delivery_ack',
          id: msg.id,
          sender: msg.from,
        }));
        resolve(msg);
      }
    });
  });

  // Setup Alice listener for ACK & Delivery Receipt
  const aliceReceiptPromise = new Promise((resolve) => {
    aliceWs.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'delivery_receipt') {
        console.log('   [Alice received delivery receipt]:', msg);
        resolve(msg);
      }
    });
  });

  // 6. Alice sends encrypted packet to Bob
  console.log('6. Alice sending message to Bob...');
  const messagePacket = {
    type: 'message',
    id: 'msg-uuid-001',
    to: 'bob',
    timestamp: Date.now(),
    ephemeralPublicKey: 'base64-ephemeral-key',
    iv: 'base64-12-byte-iv',
    ciphertext: 'base64-aes-gcm-encrypted-secret-hello-bob',
  };
  aliceWs.send(JSON.stringify(messagePacket));

  await bobReceivedPromise;
  await aliceReceiptPromise;
  console.log('   Instant relay and delivery receipt verified successfully!');

  // 7. Test Offline In-Memory Buffering: Close Bob, send message from Alice, then Bob reconnects
  console.log('7. Testing offline RAM buffering...');
  bobWs.close();
  await wait(500);

  const offlineMsgPacket = {
    type: 'message',
    id: 'msg-uuid-002',
    to: 'bob',
    timestamp: Date.now(),
    ephemeralPublicKey: 'base64-ephemeral-key-2',
    iv: 'base64-12-byte-iv-2',
    ciphertext: 'base64-aes-gcm-offline-secret',
  };

  aliceWs.send(JSON.stringify(offlineMsgPacket));
  await wait(500);

  console.log('   Bob reconnecting to drain buffered message...');
  const bobWs2 = new WebSocket(`${WS_URL}?token=${bobReg.token}`);
  const bufferedReceivedPromise = new Promise((resolve) => {
    bobWs2.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'message' && msg.id === 'msg-uuid-002') {
        console.log('   [Bob received buffered message]:', msg);
        resolve(msg);
      }
    });
  });

  await bufferedReceivedPromise;
  console.log('   Buffered message delivered and verified!');

  aliceWs.close();
  bobWs2.close();

  console.log('--- ALL SMOKE TESTS PASSED PERFECTLY ---');
  process.exit(0);
}

run().catch((err) => {
  console.error('Test failed:', err);
  process.exit(1);
});
