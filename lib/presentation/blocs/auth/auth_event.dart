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

class AuthLogoutRequested extends AuthEvent {}

class AuthProfileUpdateRequested extends AuthEvent {
  final String? displayName;
  final String? username;

  const AuthProfileUpdateRequested({this.displayName, this.username});

  @override
  List<Object?> get props => [displayName, username];
}