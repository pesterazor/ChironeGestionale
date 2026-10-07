# Encrypted Backup Format (v1)

## Goals
- Confidentiality and integrity for all clinical data contained in the encrypted backup.
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
    "schemaVersion": 5,
    "recordCounts": {
      "patients": 0,
      "clinicalNotes": 0,
      "therapyItems": 0,
      "phq9Assessments": 0,
      "gad7Assessments": 0,
      "mdqAssessments": 0,
      "beckAssessments": 0,
      "madrsAssessments": 0
    }
  }
}
```

## AAD (Additional Authenticated Data)
New backups use UTF-8 bytes of canonical JSON authenticating all envelope metadata: format, version, creation date, cipher algorithm and nonce, every KDF parameter, wrapped-key nonce, application version, schema version and record counts. Ciphertext integrity is provided by AES-GCM tags.

The decoder also supports the smaller legacy AAD. Metadata that was not authenticated by an older writer cannot be authenticated retroactively. See [BackupReview.md](BackupReview.md) for compatibility checks and limits.

## Payload content
Encrypted payload is a JSON object containing:
- all SwiftData entities (`Patient`, `ClinicalNote`, `TherapyMedication`, ...)
- clinical field values decrypted inside the AES-GCM-protected payload, then re-encrypted with the destination Mac's local key during restore
- all psychometric assessments, including BAI and BDI-II answer indices (preserving the a/b variants); see [BeckScales.md](BeckScales.md)
- MADRS item scores, assessment date, creation date, identifier, patient link and optional rater name; see [MADRS.md](MADRS.md)
- complete clinical SwiftData records; application preferences, the professional profile, the audit log and unsaved UI drafts are not included

Schema 5 encodes payload dates as JSON numbers containing seconds since Apple's reference date (2001-01-01T00:00:00Z), preserving the exact `Date` Double value. The reader also accepts the ISO-8601 strings used by schemas 2–4. Envelope and AAD dates keep their ISO-8601 representation. Earlier app builds reject schema 5 explicitly instead of attempting an incompatible restore.

The separate single-patient portability export is plaintext JSON (schema 2), explicitly identified as such in the save panel. It includes all six psychometric scales and is not a `.chdb` restore file. Local storage encrypts selected clinical text fields; this is not full-database encryption.

## Backup creation flow
1. Ask user for backup password and confirmation.
2. Generate random `DEK` (32 bytes).
3. Serialize payload.
4. Encrypt payload with `DEK` via AES-GCM (`payload`, `cipher.nonce`).
5. Derive `KEK` from password via PBKDF2 (`salt`, `iterations`).
6. Wrap `DEK` with `KEK` via AES-GCM (`wrappedDEK`, `wrappedDEKNonce`).
7. Write envelope JSON.
8. Do not persist the password. Swift-managed String/Data buffers are not guaranteed to be zeroized after use.

## Restore flow
1. Parse envelope, validate `format`, `version` and `metadata.schemaVersion`.
2. Derive `KEK` from provided password using envelope KDF params.
3. Unwrap `DEK`.
4. Decrypt payload and verify GCM tag.
5. Validate required collections and counts, duplicate IDs and patient links for every entity, and responses for every psychometric scale before replacing local data. Reject IDs already present when appending. Save prior edits, disable autosave during replacement, and commit the import in one final save; roll back if it fails.
6. Keep the local Keychain key unchanged; re-encrypt imported clinical fields with that key.

## GDPR-oriented controls
- Data minimization: store only required metadata in clear text.
- Integrity/authenticity: AES-GCM tags + AAD validation.
- Access control: backup password never persisted.
- Auditability: log backup/restore events without PHI.
- Retention: the user manages exported backup files; automatic backup expiration is not implemented.

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
| 1 | 1 | Unsupported |
| 1 | 2 | Supported; absent psychometric collections default to empty |
| 1 | 3 | Supported; Beck records and counts are required; absent MADRS collection defaults to empty |
| 1 | 4 | Supported; Beck and MADRS records and counts are required and validated before replacing data |
| 1 | 5 | Current; same complete records as schema 4, with lossless numeric payload dates |

### Rules for next versions
1. Any cryptographic incompatibility increments envelope `version`.
2. Any payload model incompatibility increments `metadata.schemaVersion`.
3. New restore support must include tests:
   - valid restore from previous supported versions
   - explicit rejection of unsupported versions
