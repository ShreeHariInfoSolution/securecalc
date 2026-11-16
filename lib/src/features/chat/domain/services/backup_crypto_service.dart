import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class BackupCryptoException implements Exception {
  final String message;
  const BackupCryptoException(this.message);

  @override
  String toString() => message;
}

/// Provides industry-standard password-based authenticated encryption (PBKDF2 + AES-256 + HMAC-SHA256)
/// for secure backup and restore of device identity and chats.
class BackupCryptoService {
  BackupCryptoService._();

  static const int pbkdf2Iterations = 100000;
  static const int keyLength = 32; // 256 bits

  /// RFC 2898 / RFC 8018 standard PBKDF2-HMAC-SHA256 implementation
  static Uint8List _deriveKey(String password, Uint8List salt, int iterations) {
    final passwordBytes = utf8.encode(password);
    final hmac = Hmac(sha256, passwordBytes);

    // Block 1: Salt || INT_32_BE(1)
    final block1Input = Uint8List(salt.length + 4);
    block1Input.setRange(0, salt.length, salt);
    block1Input[salt.length + 3] = 1; // 0x00, 0x00, 0x00, 0x01

    List<int> u = hmac.convert(block1Input).bytes;
    final f = Uint8List.fromList(u);

    for (int i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (int j = 0; j < f.length; j++) {
        f[j] ^= u[j];
      }
    }

    return f;
  }

  /// Constant-time comparison to prevent timing attacks
  static bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Encrypts a plain JSON map into a password-protected backup envelope
  static Map<String, dynamic> encryptBackupPayload({
    required Map<String, dynamic> payload,
    required String password,
  }) {
    final cleanPass = password.trim();
    if (cleanPass.isEmpty) {
      throw const BackupCryptoException('Password cannot be empty');
    }
    if (cleanPass.length < 4) {
      throw const BackupCryptoException('Password must be at least 4 characters long');
    }

    // 1. Generate random 16-byte Salt and 16-byte IV
    final rng = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
    final iv = enc.IV.fromSecureRandom(16);

    // 2. Derive 256-bit key from password + salt via PBKDF2
    final keyBytes = _deriveKey(cleanPass, salt, pbkdf2Iterations);
    final encKey = enc.Key(keyBytes);

    // 3. Encrypt payload JSON using AES-256-CBC with PKCS7
    final plaintext = jsonEncode(payload);
    final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc, padding: 'PKCS7'));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // 4. Compute HMAC-SHA256 tag over IV + Ciphertext (Encrypt-then-MAC)
    final macPayload = [...iv.bytes, ...encrypted.bytes];
    final authTag = Hmac(sha256, keyBytes).convert(macPayload).bytes;

    return {
      'app': 'SecureCalc',
      'version': 2,
      'encrypted': true,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': pbkdf2Iterations,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv.bytes),
      'tag': base64Encode(authTag),
      'ciphertext': base64Encode(encrypted.bytes),
      'exported_at': DateTime.now().toIso8601String(),
    };
  }

  /// Decrypts a password-protected backup envelope back to its original JSON map
  static Map<String, dynamic> decryptBackupPayload({
    required Map<String, dynamic> encryptedBackup,
    required String password,
  }) {
    final cleanPass = password.trim();
    if (cleanPass.isEmpty) {
      throw const BackupCryptoException('Please enter the backup password.');
    }

    try {
      final saltStr = encryptedBackup['salt']?.toString();
      final ivStr = encryptedBackup['iv']?.toString();
      final tagStr = encryptedBackup['tag']?.toString();
      final ciphertextStr = encryptedBackup['ciphertext']?.toString();
      final iterations = int.tryParse(encryptedBackup['iterations']?.toString() ?? '') ?? pbkdf2Iterations;

      if (saltStr == null || ivStr == null || tagStr == null || ciphertextStr == null) {
        throw const BackupCryptoException('Invalid backup file structure: missing cryptographic fields.');
      }

      final salt = base64Decode(saltStr);
      final ivBytes = base64Decode(ivStr);
      final expectedTag = base64Decode(tagStr);
      final cipherBytes = base64Decode(ciphertextStr);

      // 1. Derive key with entered password
      final keyBytes = _deriveKey(cleanPass, salt, iterations);

      // 2. Verify HMAC authentication tag FIRST (proves password is correct and file is untampered)
      final macPayload = [...ivBytes, ...cipherBytes];
      final computedTag = Hmac(sha256, keyBytes).convert(macPayload).bytes;

      if (!_constantTimeCompare(computedTag, expectedTag)) {
        throw const BackupCryptoException('Incorrect password. Please verify and try again.');
      }

      // 3. Decrypt ciphertext
      final encKey = enc.Key(keyBytes);
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc, padding: 'PKCS7'));
      final decryptedText = encrypter.decrypt(enc.Encrypted(cipherBytes), iv: enc.IV(ivBytes));

      final decoded = jsonDecode(decryptedText);
      if (decoded is! Map<String, dynamic>) {
        throw const BackupCryptoException('Invalid decrypted payload.');
      }
      return decoded;
    } on BackupCryptoException {
      rethrow;
    } catch (_) {
      throw const BackupCryptoException('Incorrect password or corrupted backup file.');
    }
  }

  /// Helper to check if a decoded JSON is an encrypted backup envelope
  static bool isEncryptedBackup(Map<String, dynamic> json) {
    return json['encrypted'] == true ||
        (json.containsKey('ciphertext') && json.containsKey('salt'));
  }
}
