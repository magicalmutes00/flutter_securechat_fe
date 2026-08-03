import 'package:equatable/equatable.dart';
import '../../../data/models/user_model.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  otpSent,
  error,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final String? phone;
  final String? email;
  final String? correlationId;
  final String? otpPhone;
  final String? devOtpCode;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.phone,
    this.email,
    this.correlationId,
    this.otpPhone,
    this.devOtpCode,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    String? phone,
    String? email,
    String? correlationId,
    String? otpPhone,
    String? devOtpCode,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      correlationId: correlationId ?? this.correlationId,
      otpPhone: otpPhone ?? this.otpPhone,
      devOtpCode: devOtpCode ?? this.devOtpCode,
    );
  }

  @override
  List<Object?> get props => [
        status,
        user,
        errorMessage,
        phone,
        email,
        correlationId,
        otpPhone,
        devOtpCode,
      ];
}
