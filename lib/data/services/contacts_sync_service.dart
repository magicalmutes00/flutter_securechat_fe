import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/phone_hasher.dart';
import '../models/user_model.dart';
import 'api_client.dart';

/// Reads the device address book, hashes the phone numbers locally, and asks
/// the server which of those numbers belong to registered SecureChat users.
class ContactsSyncService {
  final ApiClient _apiClient = ApiClient();

  /// Returns the registered users found among the device contacts.
  ///
  /// Returns an empty list if permission is denied.
  Future<List<User>> sync() async {
    final granted = await Permission.contacts.request().isGranted;
    if (!granted) {
      return [];
    }

    final contacts = await ContactsService.getContacts();
    final hashes = <String>{};
    final normalizedToOriginal = <String, String>{};

    for (final contact in contacts) {
      final phones = contact.phones ?? const [];
      for (final phone in phones) {
        final normalized = _normalize(phone.value ?? '');
        if (normalized.isEmpty) continue;
        final hash = PhoneHasher.hash(normalized);
        hashes.add(hash);
        normalizedToOriginal.putIfAbsent(hash, () => normalized);
      }
    }

    if (hashes.isEmpty) {
      return [];
    }

    final registered = await _apiClient.syncContacts(hashes.toList());
    return registered
        .map((json) => User.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  String _normalize(String phone) {
    // Keep digits only (drop spaces, dashes, parentheses).
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits;
  }
}
