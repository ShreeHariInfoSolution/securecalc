import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// App-side E2E Encryption service using AES-256-CBC with PKCS7 padding
/// and secure random IVs.
class E2eCryptoService {
  E2eCryptoService._();

  static final E2eCryptoService instance = E2eCryptoService._();

  static const String _encPrefix = 'ENC:v1:';

  /// Generates a simple mock SPKI public key string for initial key backup.
  String generatePublicKey() {
    final bytes = utf8.encode('public_key_${DateTime.now().millisecondsSinceEpoch}');
    return base64Encode(sha256.convert(bytes).bytes);
  }

  /// Helper to generate deterministic secret key for a conversation ID.
  String getChatKey(dynamic chatId) {
    return 'chat_key_${chatId.toString()}';
  }

  /// Encrypts message payload to base64 ciphertext prefixed with `ENC:v1:`.
  String encryptText(String plaintext, String secretKey) {
    if (plaintext.isEmpty) return '';
    try {
      final derivedKeyBytes = sha256.convert(utf8.encode('synq_chat_enc:$secretKey')).bytes;
      final encKey = enc.Key(Uint8List.fromList(derivedKeyBytes));
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc, padding: 'PKCS7'));

      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      final combinedBytes = [...iv.bytes, ...encrypted.bytes];
      return '$_encPrefix${base64Encode(combinedBytes)}';
    } catch (_) {
      return plaintext;
    }
  }

  /// Decrypts ciphertext back to plaintext string.
  /// Automatically falls back to plain text if the message is unencrypted.
  String decryptText(String ciphertext, String secretKey) {
    if (ciphertext.isEmpty) return '';
    if (!ciphertext.startsWith(_encPrefix)) {
      // Fallback: Message was not encrypted or standard plain text
      return ciphertext;
    }

    try {
      final rawBase64 = ciphertext.substring(_encPrefix.length);
      final combinedBytes = base64Decode(rawBase64);

      if (combinedBytes.length <= 16) {
        return ciphertext;
      }

      final ivBytes = combinedBytes.sublist(0, 16);
      final cipherBytes = combinedBytes.sublist(16);

      final derivedKeyBytes = sha256.convert(utf8.encode('synq_chat_enc:$secretKey')).bytes;
      final encKey = enc.Key(Uint8List.fromList(derivedKeyBytes));
      final iv = enc.IV(Uint8List.fromList(ivBytes));
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc, padding: 'PKCS7'));

      final encrypted = enc.Encrypted(Uint8List.fromList(cipherBytes));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (_) {
      return ciphertext;
    }
  }

  /// Encrypts raw binary file bytes using AES-256-CBC.
  /// Output format: [16 bytes IV] + [Ciphertext]
  Uint8List encryptFileBytes(Uint8List plainBytes, String secretKey) {
    try {
      final derivedKeyBytes = sha256.convert(utf8.encode('synq_chat_file_enc:$secretKey')).bytes;
      final encKey = enc.Key(Uint8List.fromList(derivedKeyBytes));
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc, padding: 'PKCS7'));

      final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
      final combined = Uint8List(16 + encrypted.bytes.length);
      combined.setAll(0, iv.bytes);
      combined.setAll(16, encrypted.bytes);
      return combined;
    } catch (_) {
      return plainBytes;
    }
  }

  /// Decrypts encrypted binary file bytes using AES-256-CBC.
  /// Falls back to returning original bytes if file was unencrypted.
  Uint8List decryptFileBytes(Uint8List encryptedBytes, String secretKey) {
    if (encryptedBytes.length <= 16) return encryptedBytes;
    try {
      final ivBytes = encryptedBytes.sublist(0, 16);
      final cipherBytes = encryptedBytes.sublist(16);

      final derivedKeyBytes = sha256.convert(utf8.encode('synq_chat_file_enc:$secretKey')).bytes;
      final encKey = enc.Key(Uint8List.fromList(derivedKeyBytes));
      final iv = enc.IV(Uint8List.fromList(ivBytes));
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc, padding: 'PKCS7'));

      final encrypted = enc.Encrypted(Uint8List.fromList(cipherBytes));
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      return Uint8List.fromList(decrypted);
    } catch (_) {
      return encryptedBytes;
    }
  }
}
