import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'data/services/in_app_notification_service.dart';
import 'data/services/local_storage_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/push_notification_service.dart';
import 'data/services/rtc/incoming_call_router.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/auth/auth_event.dart';
import 'presentation/blocs/auth/auth_state.dart';
import 'presentation/blocs/chat/chat_bloc.dart';
import 'presentation/blocs/theme/theme_cubit.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();
    await LocalStorageService().init();
    // Best-effort migration: drop leftover pre-removal encryption state
    // without touching cached conversations, accounts, media or settings.
    await LocalStorageService().purgeLegacyE2eeState();
  } catch (e) {
    debugPrint('Failed to initialize storage: $e');
  }

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization skipped: $e');
  }

  // Handles pushes arriving while the app is backgrounded or killed, on
  // both Android and iOS. Must be registered before runApp.
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Background push handler skipped: $e');
  }

  final notificationService = NotificationService();
  await notificationService.initialize();

  // Incoming-message hub: forwards plaintext messages to the UI and shows
  // in-app banners (foreground) or system notifications (background).
  InAppNotificationService.instance.init();

  runApp(SecureChatApp(notificationService: notificationService));
}

class SecureChatApp extends StatelessWidget {
  final NotificationService notificationService;

  const SecureChatApp({super.key, required this.notificationService});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc()..add(AuthCheckRequested()),
        ),
        BlocProvider<ChatBloc>(
          create: (context) => ChatBloc(),
        ),
        BlocProvider<ThemeCubit>(
          create: (context) => ThemeCubit()..load(),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: 'SecureChat',
            navigatorKey: appNavigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            builder: (context, child) {
              IncomingCallRouter.init(context);
              return child!;
            },
            home: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state.status == AuthStatus.initial ||
                    state.status == AuthStatus.loading) {
                  return const SplashScreen();
                }

                if (state.status == AuthStatus.authenticated) {
                  return const HomeScreen();
                }

                return const LoginScreen();
              },
            ),
          );
        },
      ),
    );
  }
}
