# Encrypted Backup Format (v1)

## Goals
- Confidentiality and integrity for all clinical data at rest and in transit.
- User-controlled recovery via backup password (cross-device restore).
- Versioned format for future migrations.
- Minimal metadata leakage.

## Cryptographic choices
- Payload encryption: `AES.GCM` (CryptoKit), 256-bit key.
- Password KDF: `PBKDF2-HMAC-SHA256` (CommonCrypto), 600000 iterations, 32-byte output.
- Data key strategy: random `DEK` (32 bytes) encrypts payload; `DEK` wrapped by `KEK` derived from password.
- Nonce size: 12 bytes for each GCM operation.
- Salt size: 16 bytes for PBKDF2.

Note: Argon2 would be preferable for password hardening, but it is not natively available in Apple SDKs.
PBKDF2 with high iteration count is the practical native choice.

## File format (JSON envelope)

```json
{
  "format": "chirone-backup",
  "version": 1,
  "createdAt": "2026-04-28T12:00:00Z",
  "cipher": {
    "algorithm": "AES-GCM-256",
    "nonceBase64": "base64...",
    "aadBase64": "base64..."
  },
  "kdf": {
    "algorithm": "PBKDF2-HMAC-SHA256",
    "saltBase64": "base64...",
    "iterations": 600000,
    "keyLength": 32
  },
  "wrappedDEKBase64": "base64...",
  "wrappedDEKNonceBase64": "base64...",
  "payloadBase64": "base64...",
  "metadata": {
    "appVersion": "1.0.0",
    "schemaVersion": 1,
    "recordCounts": {
      "patients": 0,
      "clinicalNotes": 0,
      "therapyItems": 0
    }
  }
}
```

## AAD (Additional Authenticated Data)
Use UTF-8 bytes of a canonical JSON string including:
- `format`
- `version`
- `createdAt`
- `kdf.algorithm`
- `kdf.iterations`
- `metadata.schemaVersion`

This prevents tampering of critical metadata without encrypting it.

## Payload content
Encrypted payload is a compressed JSON object containing:
- all SwiftData entities (`Patient`, `ClinicalNote`, `TherapyMedication`, ...)
- only encrypted fields stored as-is from DB (do not decrypt/re-encrypt field-level data)
- optional app settings required for restore consistency

## Backup creation flow
1. Ask user for backup password and confirmation.
2. Generate random `DEK` (32 bytes).
3. Serialize and compress payload.
4. Encrypt payload with `DEK` via AES-GCM (`payload`, `cipher.nonce`).
5. Derive `KEK` from password via PBKDF2 (`salt`, `iterations`).
6. Wrap `DEK` with `KEK` via AES-GCM (`wrappedDEK`, `wrappedDEKNonce`).
7. Write envelope JSON.
8. Zeroize plaintext password buffers where possible.

## Restore flow
1. Parse envelope, validate `format`, `version` and `metadata.schemaVersion`.
2. Derive `KEK` from provided password using envelope KDF params.
3. Unwrap `DEK`.
4. Decrypt payload and verify GCM tag.
5. Validate schema version and import transactionally.
6. Keep original local Keychain key unchanged; imported records remain field-level encrypted.

## GDPR-oriented controls
- Data minimization: store only required metadata in clear text.
- Integrity/authenticity: AES-GCM tags + AAD validation.
- Access control: backup password never persisted.
- Auditability: log backup/restore events without PHI.
- Retention: optional backup expiration policy and secure delete guidance.

## Forward compatibility
- Increment `version` for breaking changes.
- Add optional fields only (backward compatible).
- Maintain migration table from `version N` to latest.

## Version and migration policy

### Envelope `version`
- Represents cryptographic envelope compatibility (`cipher`, `kdf`, wrapping rules).
- If unsupported, restore must fail fast (`unsupportedVersion`).

### `metadata.schemaVersion`
- Represents payload schema compatibility (entity structure/fields).
- If unsupported, restore must fail fast (`unsupportedSchemaVersion`).

### Migration matrix
| Envelope version | Schema version | Restore support |
|---|---|---|
| 1 | 1 | Supported |

### Rules for next versions
1. Any cryptographic incompatibility increments envelope `version`.
2. Any payload model incompatibility increments `metadata.schemaVersion`.
3. New restore support must include tests:
   - valid restore from previous supported versions
   - explicit rejection of unsupported versions
