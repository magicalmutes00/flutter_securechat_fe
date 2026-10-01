import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

/// AES-256-GCM helpers for encrypting media attachments end-to-end.
///
/// A fresh random key + nonce is generated per attachment and the key material
/// is never stored on the server; it is delivered to the recipient inside the
/// Signal-encrypted message that references the file.
class MediaCrypto {
  MediaCrypto._();

  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int _macSizeBits = 128;

  /// Encrypts [plaintext] with [key] and [nonce] (authenticated AES-256-GCM).
  /// The returned bytes include the GCM authentication tag at the end.
  static Uint8List encrypt(
      Uint8List key, Uint8List nonce, Uint8List plaintext) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(key), _macSizeBits, nonce, Uint8List(0)),
    );
    return cipher.process(plaintext);
  }

  /// Decrypts [ciphertext] (which must include the GCM authentication tag).
  /// Throws [InvalidCipherTextException] if the key/nonce are wrong or the
  /// ciphertext was tampered with.
  static Uint8List decrypt(
      Uint8List key, Uint8List nonce, Uint8List ciphertext) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(key), _macSizeBits, nonce, Uint8List(0)),
    );
    return cipher.process(ciphertext);
  }
}
