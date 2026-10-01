import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConstants.accessTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: AppConstants.accessTokenKey);
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (e) {
              // The refresh succeeded, so the session is alive — a failed
              // retry is a request-level problem, never a reason to sign out.
              return handler.reject(error);
            }
          }
        }
        return handler.next(error);
      },
    ));
  }

  /// A bare client without interceptors, used only for token refresh so a
  /// rejected refresh cannot recurse back into this interceptor.
  Dio _bareDio() => Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));

  /// Only one refresh may be in flight at a time. On cold start several
  /// requests can 401 simultaneously; without this they would each refresh
  /// concurrently, losers would present the already-revoked token, and the
  /// resulting clearTokens() would wipe the winner's fresh pair (logout).
  Future<bool>? _refreshInFlight;

  Future<bool> _refreshToken() {
    final ongoing = _refreshInFlight;
    if (ongoing != null) return ongoing;
    final future = _doRefresh();
    _refreshInFlight = future;
    future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    return future;
  }

  Future<bool> _doRefresh() async {
    try {
      final refreshToken =
          await _storage.read(key: AppConstants.refreshTokenKey);
      if (refreshToken == null) {
        await clearTokens();
        return false;
      }

      final response = await _bareDio().post(
        '/api/auth/public/refresh-token',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        await _storage.write(
          key: AppConstants.accessTokenKey,
          value: response.data['access_token'],
        );
        await _storage.write(
          key: AppConstants.refreshTokenKey,
          value: response.data['refresh_token'],
        );
        return true;
      }
      return false;
    } on DioException catch (e) {
      // Only wipe the session when the server explicitly rejects the refresh
      // token (rotated/expired/revoked). A missing response means offline or
      // server down — the stored tokens stay valid for a later retry, so the
      // user is NOT signed out by a network blip.
      if (e.response != null &&
          (e.response!.statusCode == 400 || e.response!.statusCode == 401)) {
        await clearTokens();
      }
      return false;
    } catch (_) {
      // Transport failure — keep tokens for a later retry.
      return false;
    }
  }

  // Auth Methods
  Future<Map<String, dynamic>> exchangeFirebaseToken(String idToken) async {
    try {
      final response = await _dio.post(
        '/api/auth/public/verify-firebase-token',
        data: {'id_token': idToken},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      throw Exception('Network error: Unable to connect to server');
    }
  }

  Future<Map<String, dynamic>> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/public/register-email',
        data: {
          'email': email,
          'password': password,
          if (displayName != null) 'display_name': displayName,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      throw Exception('Network error: Unable to connect to server');
    }
  }

  Future<Map<String, dynamic>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/public/login-email',
        data: {
          'email': email,
          'password': password,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      throw Exception('Network error: Unable to connect to server');
    }
  }

  Future<Map<String, dynamic>> registerWithPhone({
    required String phone,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/public/register-phone',
        data: {
          'phone': phone,
          'password': password,
          if (displayName != null) 'display_name': displayName,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      throw Exception('Network error: Unable to connect to server');
    }
  }

  Future<Map<String, dynamic>> loginWithPhone({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/public/login-phone',
        data: {
          'phone': phone,
          'password': password,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      throw Exception('Network error: Unable to connect to server');
    }
  }

  Future<Map<String, dynamic>> requestOtp(
    String phone, {
    int countryCode = 91,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/public/send-otp',
        data: {
          'mobile_number': phone,
          'country_code': countryCode,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      throw Exception('Network error: Unable to connect to server');
    }
  }

  Future<Map<String, dynamic>> verifyOtpAndLogin({
    required String phone,
    required int countryCode,
    required String otpCode,
    required String correlationId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/auth/public/verify-otp',
        data: {
          'mobile_number': phone,
          'country_code': countryCode,
          'otp_code': otpCode,
          'correlation_id': correlationId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        return e.response!.data as Map<String, dynamic>;
      }
      throw Exception('Network error: Unable to connect to server');
    }
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/api/auth/profile');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final response = await _dio.put('/api/auth/profile', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> searchUsers(String query) async {
    // The user search endpoint requires authentication.
    final response = await _dio.get(
      '/api/auth/users/search',
      queryParameters: {'q': query},
    );
    return response.data['users'] as List<dynamic>;
  }

  // Chat Methods
  Future<List<dynamic>> getMessages(String userId,
      {int limit = 50, int skip = 0}) async {
    final response = await _dio.get(
      '/api/chat/messages/$userId',
      queryParameters: {'limit': limit, 'skip': skip},
    );
    return response.data['messages'] as List<dynamic>;
  }

  Future<List<dynamic>> getConversations() async {
    final response = await _dio.get('/api/chat/conversations');
    return response.data['conversations'] as List<dynamic>;
  }

  Future<List<dynamic>> getGroups() async {
    final response = await _dio.get('/api/groups/groups');
    return response.data['groups'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getGroup(String groupId) async {
    final response = await _dio.get('/api/groups/groups/$groupId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final response = await _dio.post(
      '/api/groups/groups',
      data: {'name': name, 'member_ids': memberIds},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getGroupMessages(
    String groupId, {
    int limit = 50,
    int skip = 0,
  }) async {
    final response = await _dio.get(
      '/api/groups/groups/$groupId/messages',
      queryParameters: {'limit': limit, 'skip': skip},
    );
    return response.data['messages'] as List<dynamic>;
  }

  Future<List<dynamic>> searchMessages(String query) async {
    final response = await _dio.get(
      '/api/chat/messages/search',
      queryParameters: {'q': query},
    );
    return response.data['messages'] as List<dynamic>;
  }

  // Status (stories) Methods
  Future<List<dynamic>> getStatuses() async {
    final response = await _dio.get('/api/status/statuses');
    return response.data['statuses'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> createStatus({
    String? text,
    String? mediaPath,
    String? mediaType,
  }) async {
    final response = await _dio.post(
      '/api/status/statuses',
      data: {
        if (text != null && text.isNotEmpty) 'text': text,
        if (mediaPath != null) 'media_path': mediaPath,
        if (mediaType != null) 'media_type': mediaType,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> markStatusViewed(String statusId) async {
    final response = await _dio.post('/api/status/statuses/$statusId/view');
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteStatus(String statusId) async {
    await _dio.delete('/api/status/statuses/$statusId');
  }

  // Push notification token methods
  Future<void> registerPushToken(String token) async {
    await _dio.post(
      '/api/push/register-token',
      data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
  }

  Future<void> unregisterPushToken(String token) async {
    await _dio.post(
      '/api/push/unregister-token',
      data: {'token': token},
    );
  }

  Future<List<dynamic>> syncContacts(List<String> phoneHashes) async {
    final response = await _dio.post(
      '/api/auth/contacts/sync',
      data: {'phone_hashes': phoneHashes},
    );
    return response.data['registered'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> data) async {
    final response = await _dio.post('/api/chat/message', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMessageStatus(
      String messageId, String status) async {
    final response = await _dio.put(
      '/api/chat/message/$messageId/status',
      data: {'status': status},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteMessage(String messageId) async {
    await _dio.delete('/api/chat/message/$messageId');
  }

  // File Upload Methods
  Future<Map<String, dynamic>> uploadFile(
    String filePath,
    String type, {
    String? filename,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final response = await _dio.post(
      '/api/files/upload/$type',
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
      ),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Downloads a file (e.g. an encrypted media blob) with authentication.
  /// Returns the raw bytes.
  Future<List<int>> downloadFileBytes(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  // E2EE Key Bundle Methods
  Future<Map<String, dynamic>> uploadKeyBundle({
    required String deviceId,
    required int registrationId,
    required String identityKeyPublic,
    required int signedPrekeyId,
    required String signedPrekeyPublic,
    required String signedPrekeySignature,
    required List<String> oneTimePrekeys,
  }) async {
    final response = await _dio.put(
      '/api/keys/upload',
      data: {
        'device_id': deviceId,
        'registration_id': registrationId,
        'identity_key_public': identityKeyPublic,
        'signed_prekey_id': signedPrekeyId,
        'signed_prekey_public': signedPrekeyPublic,
        'signed_prekey_signature': signedPrekeySignature,
        'one_time_prekeys': oneTimePrekeys,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addOneTimePrekeys({
    required String deviceId,
    required List<String> oneTimePrekeys,
  }) async {
    final response = await _dio.post(
      '/api/keys/one-time-prekeys',
      data: {'device_id': deviceId, 'one_time_prekeys': oneTimePrekeys},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> getKeyBundle(String userId) async {
    final response = await _dio.get('/api/keys/bundle/$userId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getKeyBundleStatus(String deviceId) async {
    final response = await _dio.get(
      '/api/keys/has-bundle',
      queryParameters: {'device_id': deviceId},
    );
    return response.data as Map<String, dynamic>;
  }

  // Real-time communication (WebRTC) methods
  /// Fetches the STUN/TURN (iceServers) configuration served by the backend.
  Future<Map<String, dynamic>> getRtcConfig() async {
    final response = await _dio.get('/api/rtc/config');
    return response.data as Map<String, dynamic>;
  }

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: AppConstants.accessTokenKey, value: accessToken);
    await _storage.write(
        key: AppConstants.refreshTokenKey, value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userKey);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConstants.accessTokenKey);
  }
}
