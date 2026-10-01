import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthEmailLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthEmailLoginRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

class AuthEmailRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String? displayName;

  const AuthEmailRegisterRequested({
    required this.email,
    required this.password,
    this.displayName,
  });

  @override
  List<Object?> get props => [email, password, displayName];
}

class AuthPhoneLoginRequested extends AuthEvent {
  final String phone;
  final String password;

  const AuthPhoneLoginRequested({
    required this.phone,
    required this.password,
  });

  @override
  List<Object?> get props => [phone, password];
}

class AuthPhoneRegisterRequested extends AuthEvent {
  final String phone;
  final String password;
  final String? displayName;

  const AuthPhoneRegisterRequested({
    required this.phone,
    required this.password,
    this.displayName,
  });

  @override
  List<Object?> get props => [phone, password, displayName];
}

class AuthFirebaseOtpRequested extends AuthEvent {
  final String phone;

  const AuthFirebaseOtpRequested({required this.phone});

  @override
  List<Object?> get props => [phone];
}

class AuthGoogleSignInRequested extends AuthEvent {}

class AuthFirebaseOtpVerifyRequested extends AuthEvent {
  final String otpCode;

  const AuthFirebaseOtpVerifyRequested({required this.otpCode});

  @override
  List<Object?> get props => [otpCode];
}

class AuthLogoutRequested extends AuthEvent {}

class AuthProfileUpdateRequested extends AuthEvent {
  final String? displayName;
  final String? username;
  final String? avatarUrl;

  const AuthProfileUpdateRequested(
      {this.displayName, this.username, this.avatarUrl});

  @override
  List<Object?> get props => [displayName, username, avatarUrl];
}

class AuthAvatarUploadRequested extends AuthEvent {
  final String filePath;

  const AuthAvatarUploadRequested({required this.filePath});

  @override
  List<Object?> get props => [filePath];
}

/// Clears a shown profile error. Dispatched by the UI right after displaying
/// it so an identical follow-up error still trips the listener's change
/// guard instead of being silently swallowed.
class AuthClearProfileError extends AuthEvent {
  const AuthClearProfileError();
}
