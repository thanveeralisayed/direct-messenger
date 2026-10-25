import { WebSocket } from 'ws';

const BASE_URL = 'http://localhost:8080';
const WS_URL = 'ws://localhost:8080/ws';

async function request(path, options = {}) {
  const url = `${BASE_URL}${path}`;
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    ...options,
  });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, ok: res.ok, data };
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function run() {
  console.log('=== Direct Relay Server Advanced Edge Cases & Protocol Suite ===\n');

  const uid = Date.now().toString().slice(-6);
  const alice = `alice_adv_${uid}`;
  const bob = `bob_adv_${uid}`;

  // Register Alice and Bob
  const aliceReg = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      username: alice,
      password: 'alicePassword123!',
      identityPublicKey: 'alice-identity-public-key-32-bytes-long',
    }),
  });
  if (!aliceReg.ok) throw new Error(`Alice registration failed: ${JSON.stringify(aliceReg.data)}`);

  const bobReg = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      username: bob,
      password: 'bobPassword123!',
      identityPublicKey: 'bob-identity-public-key-32-bytes-long',
    }),
  });
  if (!bobReg.ok) throw new Error(`Bob registration failed: ${JSON.stringify(bobReg.data)}`);

  // --- 1. Invalid / Malformed WebSocket Tokens ---
  console.log('Test 1: WebSocket authentication with invalid/tampered tokens...');
  const badTokenWs = new WebSocket(`${WS_URL}?token=invalid.tampered.token.12345`);
  let badTokenClosed = false;
  let closeCode = null;
  badTokenWs.on('close', (code) => {
    badTokenClosed = true;
    closeCode = code;
  });
  await wait(500);
  if (!badTokenClosed || closeCode !== 4001) {
    throw new Error(`Expected WS with bad token to be closed with 4001, got closed=${badTokenClosed}, code=${closeCode}`);
  }
  console.log('  [PASS] Tampered JWT token rejected immediately with close code 4001');

  // --- 2. Concurrent Session Takeover & Graceful Stale Socket Eviction ---
  console.log('\nTest 2: Single-user concurrent connection takeover...');
  const aliceSocket1 = new WebSocket(`${WS_URL}?token=${aliceReg.data.token}`);
  await new Promise((res, rej) => {
    aliceSocket1.on('open', res);
    aliceSocket1.on('error', rej);
  });

  let socket1Closed = false;
  let socket1Reason = '';
  aliceSocket1.on('close', (code, reason) => {
    socket1Closed = true;
    socket1Reason = reason.toString();
  });

  // Open second connection for Alice
  const aliceSocket2 = new WebSocket(`${WS_URL}?token=${aliceReg.data.token}`);
  await new Promise((res, rej) => {
    aliceSocket2.on('open', res);
    aliceSocket2.on('error', rej);
  });

  await wait(300);
  if (!socket1Closed) {
    throw new Error('Expected first connection to be closed when second connection connects');
  }
  if (!socket1Reason.includes('Replaced by new connection')) {
    throw new Error(`Expected close reason to mention replacement, got: "${socket1Reason}"`);
  }
  console.log('  [PASS] First connection cleanly terminated with reason: "Replaced by new connection"');

  // Connect Bob
  const bobSocket = new WebSocket(`${WS_URL}?token=${bobReg.data.token}`);
  await new Promise((res, rej) => {
    bobSocket.on('open', res);
    bobSocket.on('error', rej);
  });

  // Bob sends message to Alice; must arrive on aliceSocket2
  let receivedOnSocket2 = false;
  aliceSocket2.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === 'message' && msg.id === 'takeover-test-msg') {
      receivedOnSocket2 = true;
    }
  });

  bobSocket.send(JSON.stringify({
    type: 'message',
    id: 'takeover-test-msg',
    to: alice,
    timestamp: Date.now(),
    ephemeralPublicKey: 'ephem-key',
    iv: 'iv-data',
    ciphertext: 'secret-for-alice',
  }));

  await wait(400);
  if (!receivedOnSocket2) {
    throw new Error('Message from Bob was not delivered to the active replacement socket (aliceSocket2)');
  }
  console.log('  [PASS] Message routed accurately to active replacement connection');

  // --- 3. Delivery Ack & Read Receipt Ephemeral Roundtrip ---
  console.log('\nTest 3: Delivery Acknowledgment & Read Receipt roundtrip...');
  let deliveryReceiptReceived = false;
  let readReceiptReceived = false;

  bobSocket.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === 'delivery_receipt' && msg.id === 'ack-flow-msg') {
      deliveryReceiptReceived = true;
    }
    if (msg.type === 'read_receipt' && msg.id === 'ack-flow-msg') {
      readReceiptReceived = true;
    }
  });

  // Alice sends delivery ack to Bob for ack-flow-msg
  aliceSocket2.send(JSON.stringify({
    type: 'delivery_ack',
    id: 'ack-flow-msg',
    sender: bob,
  }));
  await wait(300);

  if (!deliveryReceiptReceived) {
    throw new Error('Bob did not receive delivery_receipt from Alice');
  }
  console.log('  [PASS] Delivery ack routed to Bob as delivery_receipt successfully');

  // Alice sends read receipt to Bob
  aliceSocket2.send(JSON.stringify({
    type: 'read_receipt',
    id: 'ack-flow-msg',
    sender: bob,
  }));
  await wait(300);

  if (!readReceiptReceived) {
    throw new Error('Bob did not receive read_receipt from Alice');
  }
  console.log('  [PASS] Read receipt routed to Bob successfully');

  // --- 4. Typing Indicator Online Delivery vs Offline Non-Buffering ---
  console.log('\nTest 4: Typing Indicator real-time delivery and offline non-persistence...');

  // A. Online typing delivery
  let typingDelivered = false;
  aliceSocket2.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === 'typing' && msg.from === bob && msg.isTyping === true) {
      typingDelivered = true;
    }
  });

  bobSocket.send(JSON.stringify({
    type: 'typing',
    to: alice,
    isTyping: true,
  }));
  await wait(300);
  if (!typingDelivered) throw new Error('Typing indicator not delivered to online peer');
  console.log('  [PASS] Real-time typing indicator delivered to online peer');

  // B. Bob goes offline. Alice sends typing indicator while Bob is offline.
  bobSocket.close();
  await wait(300);

  aliceSocket2.send(JSON.stringify({
    type: 'typing',
    to: bob,
    isTyping: true,
  }));
  // Also Alice sends a real message which SHOULD be buffered
  aliceSocket2.send(JSON.stringify({
    type: 'message',
    id: 'real-buffered-msg',
    to: bob,
    timestamp: Date.now(),
    ephemeralPublicKey: 'ephem-key',
    iv: 'iv-data',
    ciphertext: 'i-am-buffered',
  }));
  await wait(400);

  // Bob reconnects
  const bobSocketReconnected = new WebSocket(`${WS_URL}?token=${bobReg.data.token}`);
  const bobReceivedTypes = [];
  bobSocketReconnected.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    bobReceivedTypes.push(msg.type);
  });

  await wait(600);
  if (bobReceivedTypes.includes('typing')) {
    throw new Error('STRICT PRIVACY VIOLATION: Ephemeral typing indicator was buffered in offline RAM queue!');
  }
  if (!bobReceivedTypes.includes('message')) {
    throw new Error('Buffered text message was not delivered on reconnect');
  }
  console.log('  [PASS] Zero-storage verified: Ephemeral typing indicators are strictly ephemeral and never queued');

  // --- 5. High-Load RAM Buffer Boundary (Eviction of oldest past 500 messages) ---
  console.log('\nTest 5: RAM buffer boundary protection (eviction at 500 limit)...');
  const bufferVictim = `victim_${uid}`;
  const victimReg = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      username: bufferVictim,
      password: 'password123',
      identityPublicKey: 'victim-identity-key-32-bytes-long',
    }),
  });

  // Flood 505 offline messages to bufferVictim
  console.log('  Sending 505 messages to offline user to test FIFO queue eviction...');
  for (let i = 1; i <= 505; i++) {
    aliceSocket2.send(JSON.stringify({
      type: 'message',
      id: `flood-${i}`,
      to: bufferVictim,
      timestamp: Date.now(),
      ephemeralPublicKey: 'key',
      iv: 'iv',
      ciphertext: `msg-${i}`,
    }));
  }
  await wait(1000);

  // Connect bufferVictim and collect drained messages
  const victimWs = new WebSocket(`${WS_URL}?token=${victimReg.data.token}`);
  const victimDrainedIds = [];
  victimWs.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === 'message') {
      victimDrainedIds.push(msg.id);
    }
  });

  await wait(1500);
  console.log(`  Drained ${victimDrainedIds.length} messages from queue`);
  if (victimDrainedIds.length > 501) {
    throw new Error(`Buffer queue exceeded memory limit! Stored: ${victimDrainedIds.length}`);
  }
  // The first few messages (e.g. flood-1, flood-2, flood-3, flood-4) should have been evicted
  if (victimDrainedIds.includes('flood-1')) {
    throw new Error('Oldest message was not evicted when buffer exceeded max capacity');
  }
  // The newest message (flood-505) MUST be present
  if (!victimDrainedIds.includes('flood-505')) {
    throw new Error('Newest message was missing from buffer');
  }
  console.log('  [PASS] Oldest message safely evicted; newest messages preserved without memory exhaustion');

  // Clean close
  aliceSocket2.close();
  bobSocketReconnected.close();
  victimWs.close();

  console.log('\n=== ALL ADVANCED SERVER TESTS PASSED PERFECTLY ===');
  process.exit(0);
}

run().catch((err) => {
  console.error('\nFAILED ADVANCED TEST:', err);
  process.exit(1);
});
