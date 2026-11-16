import 'package:flutter_test/flutter_test.dart';
import 'package:securecalc/src/features/chat/domain/services/backup_crypto_service.dart';

void main() {
  group('BackupCryptoService Tests', () {
    test('Encrypt and decrypt roundtrip with correct password', () {
      final payload = {
        'app': 'SecureCalc',
        'backup_type': 'device_identity',
        'device_key': 'test_device_key_1234567890abcdef',
        'old_device_key': 'test_device_key_1234567890abcdef',
        'exported_at': '2026-11-16T12:00:00Z',
      };
      const password = 'MySecretBackupPassword!2026';

      final encrypted = BackupCryptoService.encryptBackupPayload(
        payload: payload,
        password: password,
      );

      expect(BackupCryptoService.isEncryptedBackup(encrypted), isTrue);
      expect(encrypted['app'], 'SecureCalc');
      expect(encrypted['encrypted'], isTrue);
      expect(encrypted.containsKey('ciphertext'), isTrue);
      expect(encrypted.containsKey('salt'), isTrue);
      expect(encrypted.containsKey('iv'), isTrue);
      expect(encrypted.containsKey('tag'), isTrue);

      final decrypted = BackupCryptoService.decryptBackupPayload(
        encryptedBackup: encrypted,
        password: password,
      );

      expect(decrypted['device_key'], payload['device_key']);
      expect(decrypted['old_device_key'], payload['old_device_key']);
      expect(decrypted['backup_type'], payload['backup_type']);
    });

    test('Fails cleanly when wrong password is supplied', () {
      final payload = {
        'device_key': 'test_device_key_1234567890abcdef',
      };
      final encrypted = BackupCryptoService.encryptBackupPayload(
        payload: payload,
        password: 'correct_password_123',
      );

      expect(
        () => BackupCryptoService.decryptBackupPayload(
          encryptedBackup: encrypted,
          password: 'wrong_password_456',
        ),
        throwsA(isA<BackupCryptoException>().having(
          (e) => e.message,
          'message',
          contains('Incorrect password'),
        )),
      );
    });

    test('Throws on too short password', () {
      expect(
        () => BackupCryptoService.encryptBackupPayload(
          payload: {'a': 1},
          password: '12',
        ),
        throwsA(isA<BackupCryptoException>()),
      );
    });
  });
}
