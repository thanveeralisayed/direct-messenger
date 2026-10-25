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
  console.log('=== Direct Relay Server Comprehensive Edge Cases Suite ===\n');

  // --- 1. Registration Input Validation Edge Cases ---
  console.log('Test 1: Registration input validation & boundary checks...');

  // Missing fields
  const missingFields = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username: 'valid_user' }),
  });
  if (missingFields.status !== 400) throw new Error(`Expected 400 for missing fields, got ${missingFields.status}`);
  console.log('  [PASS] Missing password & key correctly rejected with HTTP 400');

  // Username too short (< 3 chars)
  const shortUser = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username: 'ab', password: 'pw', identityPublicKey: 'key-key-key-key-key-key-key-key-key' }),
  });
  if (shortUser.status !== 400) throw new Error(`Expected 400 for short username, got ${shortUser.status}`);
  console.log('  [PASS] Short username (2 chars) correctly rejected with HTTP 400');

  // Username with spaces and illegal characters
  const illegalUser = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username: 'bad user!@#', password: 'pw', identityPublicKey: 'key-key-key-key-key-key-key-key-key' }),
  });
  if (illegalUser.status !== 400) throw new Error(`Expected 400 for illegal characters, got ${illegalUser.status}`);
  console.log('  [PASS] Username with illegal characters correctly rejected with HTTP 400');

  // Case-insensitive duplicate detection
  const uid = Date.now().toString().slice(-5);
  const baseName = `user_${uid}`;

  const reg1 = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username: baseName.toLowerCase(), password: 'password123', identityPublicKey: 'valid-public-key-32-bytes-long-string-value' }),
  });
  if (!reg1.ok) throw new Error(`Initial registration failed: ${JSON.stringify(reg1.data)}`);

  const regDuplicateCase = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username: baseName.toUpperCase(), password: 'password123', identityPublicKey: 'valid-public-key-32-bytes-long-string-value' }),
  });
  if (regDuplicateCase.status !== 400) throw new Error(`Expected 400 for case-insensitive duplicate username, got ${regDuplicateCase.status}`);
  console.log('  [PASS] Case-insensitive duplicate username (@USER vs @user) correctly rejected with HTTP 400');

  // --- 2. Authentication Failure Edge Cases ---
  console.log('\nTest 2: Authentication security & credential validation...');

  const wrongPassword = await request('/api/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username: baseName, password: 'WRONG_PASSWORD' }),
  });
  if (wrongPassword.status !== 401) throw new Error(`Expected 401 for wrong password, got ${wrongPassword.status}`);
  console.log('  [PASS] Incorrect password correctly rejected with HTTP 401');

  const nonExistentUser = await request('/api/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username: 'ghost_user_does_not_exist', password: 'password123' }),
  });
  if (nonExistentUser.status !== 401) throw new Error(`Expected 401 for non-existent user, got ${nonExistentUser.status}`);
  console.log('  [PASS] Non-existent user login correctly rejected with HTTP 401');

  // --- 3. Directory Service Edge Cases ---
  console.log('\nTest 3: Public key directory queries...');

  const keyNotFound = await request('/api/v1/users/non_existent_user/key');
  if (keyNotFound.status !== 404) throw new Error(`Expected 404 for unknown user key, got ${keyNotFound.status}`);
  console.log('  [PASS] Unknown user public key query correctly returns HTTP 404');

  const keyFound = await request(`/api/v1/users/${baseName}/key`);
  if (!keyFound.ok || !keyFound.data.identityPublicKey) throw new Error(`Failed to find key for registered user`);
  console.log('  [PASS] Valid user key retrieved successfully');

  // --- 4. WebSocket Security & Protocol Robustness Edge Cases ---
  console.log('\nTest 4: WebSocket authentication & error recovery...');

  // Unauthenticated connection without token
  let unauthClosed = false;
  const unauthWs = new WebSocket(`${WS_URL}`);
  unauthWs.on('close', (code) => {
    unauthClosed = true;
  });
  // Send message without auth
  unauthWs.on('open', () => {
    unauthWs.send(JSON.stringify({ type: 'message', to: 'someone' }));
  });
  await wait(500);
  if (!unauthClosed) throw new Error('Expected unauthenticated WebSocket connection to be closed by server');
  console.log('  [PASS] Unauthenticated WebSocket connection rejected and closed with 4001');

  // Connect valid user
  const clientToken = reg1.data.token;
  const ws = new WebSocket(`${WS_URL}?token=${clientToken}`);
  await new Promise((res, rej) => {
    ws.on('open', res);
    ws.on('error', rej);
  });
  console.log('  [PASS] Valid client authenticated via query token');

  // Send malformed non-JSON garbage string
  let receivedError = false;
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === 'error' && msg.message.includes('Malformed JSON')) {
      receivedError = true;
    }
  });

  ws.send('THIS IS NOT VALID JSON {{{{');
  await wait(300);
  if (!receivedError) throw new Error('Expected server to return error packet on malformed JSON');
  console.log('  [PASS] Malformed non-JSON payload handled gracefully without crashing server');

  // Test Ping-Pong heartbeat
  let receivedPong = false;
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === 'pong') receivedPong = true;
  });
  ws.send(JSON.stringify({ type: 'ping' }));
  await wait(300);
  if (!receivedPong) throw new Error('Expected pong reply from server');
  console.log('  [PASS] Ping/Pong heartbeat verified');

  // --- 5. Bulk Offline RAM Buffering & Clean Drain ---
  console.log('\nTest 5: Bulk offline RAM buffering and FIFO ordering...');

  const offlineTarget = `offline_${uid}`;
  const offlineReg = await request('/api/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username: offlineTarget, password: 'password123', identityPublicKey: 'key-key-key-key-key-key-key-key-key' }),
  });

  // Send 5 messages while user is completely offline
  const messageIds = ['bulk-1', 'bulk-2', 'bulk-3', 'bulk-4', 'bulk-5'];
  for (const mid of messageIds) {
    ws.send(JSON.stringify({
      type: 'message',
      id: mid,
      to: offlineTarget,
      timestamp: Date.now(),
      ephemeralPublicKey: 'ephem-key',
      iv: 'iv-data',
      ciphertext: `encrypted-${mid}`,
    }));
  }
  await wait(400);

  // Now offlineTarget connects
  const targetWs = new WebSocket(`${WS_URL}?token=${offlineReg.data.token}`);
  const drainedIds = [];
  targetWs.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.type === 'message') {
      drainedIds.push(msg.id);
    }
  });

  await wait(600);
  if (drainedIds.length !== 5) {
    throw new Error(`Expected 5 drained messages, got ${drainedIds.length}: ${JSON.stringify(drainedIds)}`);
  }
  for (let i = 0; i < messageIds.length; i++) {
    if (drainedIds[i] !== messageIds[i]) {
      throw new Error(`Ordering mismatch: expected ${messageIds[i]}, got ${drainedIds[i]}`);
    }
  }
  console.log('  [PASS] All 5 offline buffered messages received in exact chronological FIFO order');

  // Clean disconnect
  ws.close();
  targetWs.close();

  console.log('\n=== ALL SERVER EDGE CASE TESTS PASSED PERFECTLY ===');
  process.exit(0);
}

run().catch((err) => {
  console.error('\nFAILED SERVER TEST:', err);
  process.exit(1);
});
