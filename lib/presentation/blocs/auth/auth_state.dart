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
  final String? verificationId;
  final String? otpPhone;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.phone,
    this.email,
    this.verificationId,
    this.otpPhone,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    String? phone,
    String? email,
    String? verificationId,
    String? otpPhone,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      verificationId: verificationId ?? this.verificationId,
      otpPhone: otpPhone ?? this.otpPhone,
    );
  }

  @override
  List<Object?> get props => [
        status,
        user,
        errorMessage,
        phone,
        email,
        verificationId,
        otpPhone,
      ];
}
