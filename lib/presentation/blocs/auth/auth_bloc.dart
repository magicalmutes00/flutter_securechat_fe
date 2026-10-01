import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/api_client.dart';
import '../../../data/services/media_cache_service.dart';
import '../../../data/services/media_preparation_service.dart';
import '../../../data/services/firebase_auth_service.dart';
import '../../../data/services/local_storage_service.dart';
import '../../../data/services/push_notification_service.dart';
import '../../../data/services/websocket_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiClient _apiClient = ApiClient();
  final WebSocketService _wsService = WebSocketService();
  final LocalStorageService _localStorage = LocalStorageService();
  final FirebaseAuthService _firebaseAuthService = FirebaseAuthService.instance;

  AuthBloc() : super(const AuthState()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthEmailLoginRequested>(_onAuthEmailLoginRequested);
    on<AuthEmailRegisterRequested>(_onAuthEmailRegisterRequested);
    on<AuthPhoneLoginRequested>(_onAuthPhoneLoginRequested);
    on<AuthPhoneRegisterRequested>(_onAuthPhoneRegisterRequested);
    on<AuthFirebaseOtpRequested>(_onAuthFirebaseOtpRequested);
    on<AuthFirebaseOtpVerifyRequested>(_onAuthFirebaseOtpVerifyRequested);
    on<AuthGoogleSignInRequested>(_onAuthGoogleSignInRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
    on<AuthProfileUpdateRequested>(_onAuthProfileUpdateRequested);
    on<AuthAvatarUploadRequested>(_onAuthAvatarUploadRequested);
    on<AuthClearProfileError>(_onAuthClearProfileError);
  }

  /// Last-known profile, so a cold start without connectivity can still
  /// open the app (offline with cached conversations) instead of forcing a
  /// login. Refreshed on every successful online auth check.
  static const String _cachedProfileKey = 'securechat.cached_profile';

  Future<void> _cacheProfile(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedProfileKey, jsonEncode(user.toJson()));
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<User?> _cachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachedProfileKey);
      if (raw == null) return null;
      final user = User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return user.id.isEmpty ? null : user;
    } catch (_) {
      return null;
    }
  }

  Future<void> _connectWsBestEffort(String userId) async {
    _wsService.setCurrentUserId(userId);
    try {
      await _wsService.connect();
    } catch (e) {
      // Offline or server down: the socket's own reconnect loop picks it up
      // later. Never fail authentication because of the socket.
      debugPrint('WS connect deferred: $e');
    }
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
    ));

    // A storage read failure (keystore hiccup) is NOT proof of no session —
    // only positively-absent tokens sign out. Anything else falls back to
    // the cached profile (offline mode) rather than the login screen.
    String? token;
    var storageOk = true;
    try {
      token = await _apiClient.getAccessToken();
    } catch (_) {
      storageOk = false;
    }
    if (storageOk && token == null) {
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: null,
      ));
      return;
    }

    // Proactive rotation while online: a day-idle cold start refreshes
    // cleanly here instead of 401-chasing on the first request. Best-effort
    // — the getProfile path below still handles every failure mode.
    try {
      await _apiClient.refreshIfExpiringSoon();
    } catch (_) {}

    try {
      try {
        // The interceptor transparently refreshes an expired access token.
        final profileData = await _apiClient.getProfile();
        final user = User.fromJson(profileData);
        await _cacheProfile(user);
        await _connectWsBestEffort(user.id);

        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
      } catch (_) {
        // Sign out ONLY when the tokens are confirmed gone (the interceptor
        // wipes them exactly when the server rejects the session). Every
        // other failure — offline, server waking, keystore hiccup — keeps
        // the cached profile instead of dropping to login.
        var tokensGone = false;
        try {
          tokensGone = await _apiClient.getAccessToken() == null;
        } catch (_) {
          tokensGone = false;
        }
        if (storageOk && tokensGone) {
          emit(state.copyWith(
            status: AuthStatus.unauthenticated,
            errorMessage: null,
          ));
          return;
        }
        final cached = await _cachedProfile();
        if (cached == null) {
          emit(state.copyWith(
            status: AuthStatus.unauthenticated,
            errorMessage: null,
          ));
          return;
        }
        await _connectWsBestEffort(cached.id);
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: cached,
          errorMessage: null,
        ));
      }
    } catch (_) {
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: null,
      ));
    }
  }

  Future<void> _onAuthEmailLoginRequested(
    AuthEmailLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      email: event.email,
      errorMessage: null,
    ));

    try {
      final idToken = await _firebaseAuthService.loginWithEmail(
        email: event.email,
        password: event.password,
      );
      await _completeFirebaseAuth(idToken, emit);
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: _friendlyAuthError(e),
      ));
    } catch (e) {
      String errorMsg = 'Login failed';
      if (e.toString().contains('Network error')) {
        errorMsg = 'Unable to connect to server. Please check your connection.';
      } else if (e.toString().contains('SocketException')) {
        errorMsg = 'Unable to connect to server.';
      }
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: errorMsg,
      ));
    }
  }

  Future<void> _onAuthEmailRegisterRequested(
    AuthEmailRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      email: event.email,
      errorMessage: null,
    ));

    try {
      final idToken = await _firebaseAuthService.registerWithEmail(
        email: event.email,
        password: event.password,
        displayName: event.displayName,
      );
      await _completeFirebaseAuth(idToken, emit);
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: _friendlyAuthError(e),
      ));
    } catch (e) {
      String errorMsg = 'Registration failed';
      if (e.toString().contains('Network error')) {
        errorMsg = 'Unable to connect to server. Please check your connection.';
      } else if (e.toString().contains('SocketException')) {
        errorMsg = 'Unable to connect to server.';
      }
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: errorMsg,
      ));
    }
  }

  Future<void> _onAuthPhoneLoginRequested(
    AuthPhoneLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      phone: event.phone,
      errorMessage: null,
    ));

    try {
      final result = await _apiClient.loginWithPhone(
        phone: event.phone,
        password: event.password,
      );

      final success =
          result['success'] == true || result.containsKey('access_token');
      final errorMessage = result['error'] ?? result['message'];

      if (success) {
        final user = User.fromJson(result['user']);
        await _apiClient.saveTokens(
          result['access_token'],
          result['refresh_token'],
        );

        _wsService.setCurrentUserId(user.id);
        await _wsService.connect();

        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
      } else {
        emit(state.copyWith(
          status: AuthStatus.error,
          errorMessage: errorMessage ?? 'Login failed',
        ));
      }
    } catch (e) {
      String errorMsg = 'Login failed';
      if (e.toString().contains('Network error')) {
        errorMsg = 'Unable to connect to server. Please check your connection.';
      } else if (e.toString().contains('SocketException')) {
        errorMsg = 'Unable to connect to server.';
      }
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: errorMsg,
      ));
    }
  }

  Future<void> _onAuthPhoneRegisterRequested(
    AuthPhoneRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      phone: event.phone,
      errorMessage: null,
    ));

    try {
      final result = await _apiClient.registerWithPhone(
        phone: event.phone,
        password: event.password,
        displayName: event.displayName,
      );

      final hasAccessToken =
          result.containsKey('access_token') || result.containsKey('token');
      final hasUser = result.containsKey('user');
      final isSuccess =
          result['success'] == true || (hasAccessToken && hasUser);

      if (isSuccess) {
        final userData = result['user'] ?? result;
        final user = User.fromJson(userData as Map<String, dynamic>);
        final token = result['access_token'] ?? result['token'];
        final refreshToken = result['refresh_token'] ?? result['refreshToken'];

        await _apiClient.saveTokens(token, refreshToken);

        _wsService.setCurrentUserId(user.id);
        await _wsService.connect();

        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
      } else {
        final errorMsg =
            result['error'] ?? result['message'] ?? 'Registration failed';
        emit(state.copyWith(
          status: AuthStatus.error,
          errorMessage: errorMsg,
        ));
      }
    } catch (e) {
      String errorMsg = 'Registration failed';
      if (e.toString().contains('Network error')) {
        errorMsg = 'Unable to connect to server. Please check your connection.';
      } else if (e.toString().contains('SocketException')) {
        errorMsg = 'Unable to connect to server.';
      }
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: errorMsg,
      ));
    }
  }

  Future<void> _onAuthFirebaseOtpRequested(
    AuthFirebaseOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      phone: event.phone,
      errorMessage: null,
    ));

    try {
      final result = await _firebaseAuthService.sendCode(event.phone);
      switch (result) {
        case PhoneCodeSent(:final verificationId):
          emit(state.copyWith(
            status: AuthStatus.otpSent,
            verificationId: verificationId,
            otpPhone: event.phone,
            errorMessage: null,
          ));
        case PhoneAutoVerified(:final idToken):
          await _completeFirebaseAuth(idToken, emit);
      }
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: _friendlyAuthError(e),
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onAuthFirebaseOtpVerifyRequested(
    AuthFirebaseOtpVerifyRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
    ));

    try {
      final idToken =
          await _firebaseAuthService.verifyCode(event.otpCode.trim());
      await _completeFirebaseAuth(idToken, emit);
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: _friendlyAuthError(e),
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onAuthGoogleSignInRequested(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
    ));

    try {
      final idToken = await _firebaseAuthService.signInWithGoogle();
      await _completeFirebaseAuth(idToken, emit);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // User closed the account picker — reset quietly instead of showing
        // an error.
        emit(const AuthState(status: AuthStatus.unauthenticated));
        return;
      }
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: _friendlyAuthError(e),
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Exchanges a Firebase ID token for a SecureChat session and connects the
  /// WebSocket. Shared by OTP entry, instant verification, and Google sign-in.
  Future<void> _completeFirebaseAuth(
      String idToken, Emitter<AuthState> emit) async {
    debugPrint('[AuthBloc] exchanging Firebase token with backend...');
    final result = await _firebaseAuthService.exchangeToken(idToken);
    debugPrint('[AuthBloc] backend exchange response: $result');

    final success =
        result['success'] == true || result.containsKey('access_token');
    if (!success) {
      throw Exception(result['error'] ?? 'Authentication failed');
    }

    await _apiClient.saveTokens(
      result['access_token'],
      result['refresh_token'],
    );

    final user = User.fromJson(result['user'] as Map<String, dynamic>);
    await _cacheProfile(user);

    debugPrint('[AuthBloc] connecting WebSocket for user ${user.id}...');
    _wsService.setCurrentUserId(user.id);
    await _wsService.connect();

    emit(state.copyWith(
      status: AuthStatus.authenticated,
      user: user,
      phone: null,
      verificationId: null,
      otpPhone: null,
      errorMessage: null,
    ));
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-verification-code':
        return 'Incorrect code. Please try again.';
      case 'invalid-phone-number':
        return 'Invalid phone number. Use the international format (e.g. +1234567890).';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'session-expired':
        return 'The verification code has expired. Please request a new one.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in instead.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-not-found':
        return 'No account found for this email. Please register first.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return error.message ?? 'Verification failed';
    }
  }

  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentUserId = state.user?.id;
    await _firebaseAuthService.signOut();
    await _wsService.disconnect();
    if (currentUserId != null) {
      // Release the FCM token so this device stops receiving pushes for the
      // account before the session is torn down.
      await PushNotificationHandler().unregister();
    }
    await _apiClient.clearTokens();
    if (currentUserId != null) {
      await _localStorage.clearUserData(currentUserId);
      // Drop any leftover pre-removal encryption state for the account.
      await _localStorage.purgeLegacyE2eeState(userId: currentUserId);
    }
    // Cached media (images, avatars) must not survive logout either.
    await MediaCacheService().clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedProfileKey);
    } catch (_) {
      // Best-effort only.
    }
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  /// Profile edits run under [AuthState.isSavingProfile] with the global
  /// status untouched: main.dart routes off [AuthStatus], so flipping it to
  /// loading/error here boots the user to splash/login mid-save. Failures
  /// surface as [AuthState.profileErrorMessage] on the profile screen only.
  Future<void> _onAuthProfileUpdateRequested(
    AuthProfileUpdateRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      clearProfileError: true,
      isSavingProfile: true,
    ));

    try {
      final data = <String, dynamic>{};
      if (event.displayName != null) data['display_name'] = event.displayName;
      if (event.username != null) data['username'] = event.username;
      if (event.avatarUrl != null) data['avatar_url'] = event.avatarUrl;

      final result = await _apiClient.updateProfile(data);
      final user = User.fromJson(result);
      await _cacheProfile(user);

      emit(state.copyWith(
        isSavingProfile: false,
        user: user,
      ));
    } catch (e) {
      emit(state.copyWith(
        isSavingProfile: false,
        profileErrorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onAuthAvatarUploadRequested(
    AuthAvatarUploadRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      clearProfileError: true,
      isSavingProfile: true,
    ));

    try {
      // Same pipeline as chat sends: shrink, gate, upload. A rejected file
      // fails here with an actionable message instead of after a full
      // upload — and, crucially, without touching the global auth status.
      final original = event.filePath;
      final sendPath = await MediaPreparationService.prepareImage(
        filePath: original,
        messageType: AppConstants.messageTypeImage,
      );
      try {
        await MediaPreparationService.validate(
          filePath: sendPath,
          messageType: AppConstants.messageTypeImage,
        );
      } on MediaValidationException {
        await MediaPreparationService.deleteTemp(sendPath, original);
        rethrow;
      }
      final result = await _apiClient.uploadFile(sendPath, 'image');
      await MediaPreparationService.deleteTemp(sendPath, original);
      if (result['success'] == true) {
        final avatarUrl = result['url'] as String?;
        if (avatarUrl != null) {
          final profileResult =
              await _apiClient.updateProfile({'avatar_url': avatarUrl});
          final user = User.fromJson(profileResult);
          await _cacheProfile(user);
          emit(state.copyWith(
            isSavingProfile: false,
            user: user,
          ));
          return;
        }
      }
      emit(state.copyWith(
        isSavingProfile: false,
        profileErrorMessage: 'Failed to upload avatar',
      ));
    } catch (e) {
      emit(state.copyWith(
        isSavingProfile: false,
        profileErrorMessage: _friendlyUploadError(e),
      ));
    }
  }

  void _onAuthClearProfileError(
    AuthClearProfileError event,
    Emitter<AuthState> emit,
  ) {
    if (state.profileErrorMessage == null) return;
    emit(state.copyWith(clearProfileError: true));
  }

  String _friendlyUploadError(Object e) {
    if (e is MediaValidationException) return e.message;
    if (e is ApiException) {
      switch (e.code) {
        case 'file_too_large':
          return 'That photo is too large for a profile picture.';
        case 'extension_not_allowed':
          return "That file type can't be used as a photo.";
        case 'unauthorized':
          return 'Your session expired — please log in again.';
      }
    }
    return 'Could not set that photo. Please try another.';
  }
}
