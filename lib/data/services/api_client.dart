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
              await clearTokens();
              return handler.reject(error);
            }
          }
        }
        return handler.next(error);
      },
    ));
  }

    Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: AppConstants.refreshTokenKey);
      if (refreshToken == null) {
        await clearTokens();
        return false;
      }

      final response = await _dio.post(
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
    } catch (e) {
      // Clear tokens on refresh failure to prevent stuck auth state
      await clearTokens();
      return false;
    }
  }

  // Auth Methods
  Future<Map<String, dynamic>> verifyFirebaseToken(String idToken) async {
    final response = await _dio.post(
      '/api/auth/public/verify-firebase-token',
      data: {'id_token': idToken},
    );
    return response.data as Map<String, dynamic>;
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

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/api/auth/profile');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final response = await _dio.put('/api/auth/profile', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final response = await _dio.get(
      '/api/auth/public/users/search',
      queryParameters: {'q': query},
    );
    return response.data['users'] as List<dynamic>;
  }

  // Chat Methods
  Future<List<dynamic>> getMessages(String userId, {int limit = 50, int skip = 0}) async {
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

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> data) async {
    final response = await _dio.post('/api/chat/message', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMessageStatus(String messageId, String status) async {
    final response = await _dio.put(
      '/api/chat/message/$messageId/status',
      data: {'status': status},
    );
    return response.data as Map<String, dynamic>;
  }

  // File Upload Methods
  Future<Map<String, dynamic>> uploadFile(String filePath, String type) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
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

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: AppConstants.accessTokenKey, value: accessToken);
    await _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken);
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
