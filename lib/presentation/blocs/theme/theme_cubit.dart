import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app's [ThemeMode]. Defaults to following the system; the user's
/// explicit choice is persisted so it survives restarts.
class ThemeCubit extends Cubit<ThemeMode> {
  static const String _key = 'securechat.theme_mode';

  ThemeCubit() : super(ThemeMode.system);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light':
        emit(ThemeMode.light);
      case 'dark':
        emit(ThemeMode.dark);
      default:
        emit(ThemeMode.system);
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (state == mode) return;
    emit(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
