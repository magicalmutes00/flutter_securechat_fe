import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/api_client.dart';
import '../../../data/services/websocket_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiClient _apiClient = ApiClient();
  final WebSocketService _wsService = WebSocketService();

  AuthBloc() : super(const AuthState()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthEmailLoginRequested>(_onAuthEmailLoginRequested);
    on<AuthEmailRegisterRequested>(_onAuthEmailRegisterRequested);
    on<AuthPhoneLoginRequested>(_onAuthPhoneLoginRequested);
    on<AuthPhoneRegisterRequested>(_onAuthPhoneRegisterRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
    on<AuthProfileUpdateRequested>(_onAuthProfileUpdateRequested);
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
    ));

    try {
      final token = await _apiClient.getAccessToken();
      if (token != null) {
        final profileData = await _apiClient.getProfile();
        final user = User.fromJson(profileData);

        _wsService.setCurrentUserId(user.id);
        await _wsService.connect();

        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: null,
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
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
      final result = await _apiClient.loginWithEmail(
        email: event.email,
        password: event.password,
      );

      final success = result['success'] == true || result.containsKey('access_token');
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
      final result = await _apiClient.registerWithEmail(
        email: event.email,
        password: event.password,
        displayName: event.displayName,
      );

      print('DEBUG register result: $result');

      // Check for various success indicators
      final hasAccessToken = result.containsKey('access_token') || result.containsKey('token');
      final hasUser = result.containsKey('user');
      final isSuccess = result['success'] == true || (hasAccessToken && hasUser);

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
        final errorMsg = result['error'] ?? result['message'] ?? 'Registration failed';
        print('DEBUG register failed: $errorMsg');
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

      final success = result['success'] == true || result.containsKey('access_token');
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

      final hasAccessToken = result.containsKey('access_token') || result.containsKey('token');
      final hasUser = result.containsKey('user');
      final isSuccess = result['success'] == true || (hasAccessToken && hasUser);

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
        final errorMsg = result['error'] ?? result['message'] ?? 'Registration failed';
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

  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _wsService.disconnect();
    await _apiClient.clearTokens();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> _onAuthProfileUpdateRequested(
    AuthProfileUpdateRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
    ));

    try {
      final data = <String, dynamic>{};
      if (event.displayName != null) data['display_name'] = event.displayName;
      if (event.username != null) data['username'] = event.username;

      final result = await _apiClient.updateProfile(data);
      final user = User.fromJson(result);

      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        errorMessage: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }
}