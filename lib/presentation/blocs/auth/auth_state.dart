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

  /// Profile edits (name/avatar) run under these flags while [status] stays
  /// `authenticated`: routing in main.dart keys off [status], so profile work
  /// must never flip it to loading/error (which boots the user to splash /
  /// login mid-upload).
  final bool isSavingProfile;
  final String? profileErrorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.phone,
    this.email,
    this.verificationId,
    this.otpPhone,
    this.isSavingProfile = false,
    this.profileErrorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    String? phone,
    String? email,
    String? verificationId,
    String? otpPhone,
    bool? isSavingProfile,
    String? profileErrorMessage,

    /// copyWith can't distinguish "no change" from "set to null", so a shown
    /// profile error is cleared explicitly.
    bool clearProfileError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      verificationId: verificationId ?? this.verificationId,
      otpPhone: otpPhone ?? this.otpPhone,
      isSavingProfile: isSavingProfile ?? this.isSavingProfile,
      profileErrorMessage: clearProfileError
          ? null
          : (profileErrorMessage ?? this.profileErrorMessage),
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
        isSavingProfile,
        profileErrorMessage,
      ];
}
