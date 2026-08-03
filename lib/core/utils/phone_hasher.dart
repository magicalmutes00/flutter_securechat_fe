import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Hashes phone numbers for privacy-preserving contact discovery.
///
/// MUST match the backend implementation in
/// `flutter_securechat_bk/lib/services/user_service.dart` (`_hashPhone`),
/// which is `sha256(phone.trim())` as a lowercase hex string.
class PhoneHasher {
  PhoneHasher._();

  static String hash(String phone) =>
      sha256.convert(utf8.encode(phone.trim())).toString();
}
