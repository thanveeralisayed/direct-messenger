import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { UserRecord } from './types.js';

/**
 * User Identity Directory
 * NOTE: Strictly stores usernames, credentials, and identity public keys.
 * NO CHAT MESSAGES, MEDIA, OR CONVERSATIONS ARE EVER PERSISTED HERE.
 */
export class UserDatabase {
  private filePath: string;
  private users: Map<string, UserRecord> = new Map();

  constructor(dataDir: string = './data') {
    if (!fs.existsSync(dataDir)) {
      fs.mkdirSync(dataDir, { recursive: true });
    }
    this.filePath = path.join(dataDir, 'users.json');
    this.load();
  }

  private load(): void {
    if (fs.existsSync(this.filePath)) {
      try {
        const raw = fs.readFileSync(this.filePath, 'utf-8');
        const list: UserRecord[] = JSON.parse(raw);
        for (const user of list) {
          this.users.set(user.username.toLowerCase(), user);
        }
      } catch (err) {
        console.error('Failed to load user database, starting fresh:', err);
      }
    }
  }

  private save(): void {
    const list = Array.from(this.users.values());
    fs.writeFileSync(this.filePath, JSON.stringify(list, null, 2), 'utf-8');
  }

  public hashPassword(password: string, salt: string): string {
    return crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
  }

  public register(username: string, password: string, identityPublicKey: string): UserRecord {
    const normalized = username.trim().toLowerCase();
    if (this.users.has(normalized)) {
      throw new Error('Username already exists');
    }
    if (!/^[a-zA-Z0-9_]{3,30}$/.test(username)) {
      throw new Error('Username must be 3-30 characters (letters, numbers, underscore only)');
    }
    if (!identityPublicKey || identityPublicKey.length < 32) {
      throw new Error('Invalid identity public key provided');
    }

    const salt = crypto.randomBytes(16).toString('hex');
    const passwordHash = this.hashPassword(password, salt);

    const record: UserRecord = {
      username: normalized,
      passwordHash,
      salt,
      identityPublicKey,
      createdAt: Date.now(),
    };

    this.users.set(normalized, record);
    this.save();
    return record;
  }

  public authenticate(username: string, password: string): UserRecord | null {
    const normalized = username.trim().toLowerCase();
    const record = this.users.get(normalized);
    if (!record) return null;

    const hash = this.hashPassword(password, record.salt);
    if (crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(record.passwordHash))) {
      return record;
    }
    return null;
  }

  public getPublicKey(username: string): string | null {
    const normalized = username.trim().toLowerCase();
    const record = this.users.get(normalized);
    return record ? record.identityPublicKey : null;
  }

  public updatePublicKey(username: string, newPublicKey: string): void {
    const normalized = username.trim().toLowerCase();
    const record = this.users.get(normalized);
    if (record) {
      record.identityPublicKey = newPublicKey;
      this.save();
    }
  }

  public userExists(username: string): boolean {
    return this.users.has(username.trim().toLowerCase());
  }
}
