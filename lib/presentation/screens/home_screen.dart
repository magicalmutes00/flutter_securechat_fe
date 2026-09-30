import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/notification_service.dart';
import '../../data/services/push_notification_service.dart';
import '../../data/services/rtc/call_manager.dart';
import '../blocs/chat/chat_bloc.dart';
import '../blocs/chat/chat_event.dart';
import '../blocs/chat/chat_state.dart';
import 'chats_tab.dart';
import 'profile_tab.dart';
import 'status_tab.dart';

/// App shell: bottom navigation across Chats / Status / Profile.
/// Tab content lives in dedicated files; this widget only owns the shell,
/// global init (calls, push) and the unread badge.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    context.read<ChatBloc>().add(ChatLoadConversations());
    _initCalls();
    _initPush();
  }

  Future<void> _initCalls() async {
    try {
      await CallManager.instance.init();
    } catch (e) {
      debugPrint('Failed to initialize call manager: $e');
    }
  }

  Future<void> _initPush() async {
    try {
      await PushNotificationHandler()
          .init(notificationService: NotificationService());
    } catch (e) {
      debugPrint('Failed to initialize push notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          ChatsTab(),
          StatusTab(),
          ProfileTab(),
        ],
      ),
      bottomNavigationBar: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, state) {
          final totalUnread =
              state.unreadCounts.values.fold<int>(0, (a, b) => a + b);
          return NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) =>
                setState(() => _currentIndex = index),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: totalUnread > 0 && _currentIndex != 0,
                  label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                selectedIcon: Badge(
                  isLabelVisible: totalUnread > 0 && _currentIndex != 0,
                  label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
                  child: const Icon(Icons.chat_bubble),
                ),
                label: 'Chats',
              ),
              const NavigationDestination(
                icon: Icon(Icons.donut_large_outlined),
                selectedIcon: Icon(Icons.donut_large),
                label: 'Status',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }
}
