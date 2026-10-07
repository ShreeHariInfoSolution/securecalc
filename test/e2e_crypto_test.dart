import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AES-256-CBC Text Encryption and Decryption Roundtrip', () {
    final crypto = E2eCryptoTestService();
    const key = 'chat_key_123';
    const originalText = 'Hello! This is a secret encrypted message 🎉 with special chars & numbers 12345.';

    final encrypted = crypto.encryptText(originalText, key);
    expect(encrypted.startsWith('ENC:v1:'), isTrue);
    expect(encrypted, isNot(contains(originalText)));

    final decrypted = crypto.decryptText(encrypted, key);
    expect(decrypted, equals(originalText));
  });

  test('Fallback to plaintext if message is not encrypted', () {
    final crypto = E2eCryptoTestService();
    const key = 'chat_key_123';
    const plain = 'Legacy plain text message';

    final result = crypto.decryptText(plain, key);
    expect(result, equals(plain));
  });

  test('Decryption fails gracefully with wrong key', () {
    final crypto = E2eCryptoTestService();
    const key1 = 'chat_key_123';
    const key2 = 'chat_key_456';
    const originalText = 'Secret payload';

    final encrypted = crypto.encryptText(originalText, key1);
    final decrypted = crypto.decryptText(encrypted, key2);

    expect(decrypted, equals(encrypted));
  });

  test('AES-256-CBC File Bytes Encryption and Decryption Roundtrip', () {
    final crypto = E2eCryptoTestService();
    const key = 'chat_key_789';
    final sampleFileBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5, 255]);

    final encryptedBytes = crypto.encryptFileBytes(sampleFileBytes, key);
    expect(encryptedBytes.length, greaterThan(16));
    expect(encryptedBytes, isNot(equals(sampleFileBytes)));

    final decryptedBytes = crypto.decryptFileBytes(encryptedBytes, key);
    expect(decryptedBytes, equals(sampleFileBytes));
  });
}

class E2eCryptoTestService {
  static const String _encPrefix = 'ENC:v1:';

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

  String decryptText(String ciphertext, String secretKey) {
    if (ciphertext.isEmpty) return '';
    if (!ciphertext.startsWith(_encPrefix)) {
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
