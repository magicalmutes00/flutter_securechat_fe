import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../presentation/blocs/chat/chat_bloc.dart';
import '../../presentation/screens/chat_screen.dart';
import '../../presentation/screens/group_chat_screen.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'api_client.dart';
import 'e2ee/e2ee_service.dart';
import 'local_storage_service.dart';
import 'notification_service.dart';
import 'rtc/incoming_call_router.dart';
import 'websocket_service.dart';

/// Central incoming-message notification hub.
///
/// Sits between the raw WebSocket streams and the UI:
///  - decrypts every incoming message exactly once and re-broadcasts it on
///    [decryptedMessageStream] / [decryptedGroupMessageStream] (ChatBloc and
///    GroupChatScreen consume these instead of the raw streams — decrypting
///    the same Double-Ratchet ciphertext twice would fail),
///  - while the app is in the foreground, surfaces an in-app banner toast at
///    the top of the screen for messages arriving in other conversations
///    (tapping it opens the chat),
///  - while the app is backgrounded, posts a system notification instead.
class InAppNotificationService with WidgetsBindingObserver {
  static final InAppNotificationService instance = InAppNotificationService._();

  InAppNotificationService._();

  final WebSocketService _ws = WebSocketService();
  final NotificationService _notifications = NotificationService();
  final LocalStorageService _storage = LocalStorageService();

  StreamSubscription<Message>? _messageSub;
  StreamSubscription<Message>? _groupMessageSub;
  StreamSubscription<NotificationPayload>? _notificationTapSub;

  final _decryptedMessageController = StreamController<Message>.broadcast();
  final _decryptedGroupMessageController =
      StreamController<Message>.broadcast();

  /// 1:1 messages, already decrypted.
  Stream<Message> get decryptedMessageStream =>
      _decryptedMessageController.stream;

  /// Group messages, already decrypted.
  Stream<Message> get decryptedGroupMessageStream =>
      _decryptedGroupMessageController.stream;

  bool _appInForeground = true;
  bool _initialized = false;

  /// Conversation (peer userId or groupId) whose chat screen is currently
  /// open; messages for it never notify.
  String? _viewingChatId;

  OverlayEntry? _activeBanner;

  /// Whether an in-app banner is currently visible.
  bool get hasActiveBanner => _activeBanner != null;

  void init() {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    _appInForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

    _messageSub = _ws.messageStream.listen(
      (message) => unawaited(_handleIncoming(message, isGroup: false)),
    );
    _groupMessageSub = _ws.groupMessageStream.listen(
      (message) => unawaited(_handleIncoming(message, isGroup: true)),
    );

    // Tapping a system notification opens the originating conversation.
    _notificationTapSub =
        _notifications.notificationStream.listen(_onTapPayload);
  }

  /// The chat screen that is currently on top must register itself so its
  /// messages don't trigger banners.
  void setViewingChat(String? chatId) {
    _viewingChatId = chatId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _handleIncoming(Message raw, {required bool isGroup}) async {
    var message = raw;
    final me = _ws.currentUserId;

    // Decrypt here so downstream consumers (ChatBloc, GroupChatScreen)
    // never touch ciphertext twice.
    try {
      if (isGroup) {
        if (message.encryption == 'sgkey' &&
            message.cipherBody != null &&
            message.groupId != null &&
            me != null) {
          final plaintext = await E2eeService.instance.decryptGroupText(
            currentUserId: me,
            groupId: message.groupId!,
            senderId: message.senderId,
            cipherBody: message.cipherBody!,
            distributionB64: message.distribution,
          );
          message = message.copyWith(
            content: plaintext,
            encryption: 'none',
            cipherBody: null,
            cipherType: null,
            distribution: null,
          );
        }
        _decryptedGroupMessageController.add(message);
      } else {
        if (me != null) {
          message = await E2eeService.instance
              .decryptMessage(message, currentUserId: me);
        }
        _decryptedMessageController.add(message);
      }
    } catch (_) {
      // Decryption failed: hand the ciphertext on so the chat UI can render
      // its "unable to decrypt" placeholder.
      (isGroup ? _decryptedGroupMessageController : _decryptedMessageController)
          .add(message);
      return;
    }

    if (me == null || message.senderId == me) return;

    final isViewingThisChat = isGroup
        ? message.groupId != null && message.groupId == _viewingChatId
        : message.senderId == _viewingChatId;

    if (!_appInForeground) {
      await _notifications.showLocalNotification(
        title: _resolveSenderName(message.senderId),
        body: message.isTextMessage && message.content.isNotEmpty
            ? message.content
            : _messageTypeLabel(message.messageType),
        senderId: message.senderId,
        data: {
          'sender_id': message.senderId,
          'message_id': message.id,
          'is_group': isGroup,
          if (isGroup && message.groupId != null) 'group_id': message.groupId,
        },
      );
      return;
    }

    if (isViewingThisChat) return;

    _showBanner(
      title: _resolveSenderName(message.senderId),
      body: message.isTextMessage && message.content.isNotEmpty
          ? message.content
          : _messageTypeLabel(message.messageType),
      onOpen: () => unawaited(_openConversation(message, isGroup: isGroup)),
    );
  }

  String _resolveSenderName(String senderId) {
    final me = _ws.currentUserId;
    if (me != null) {
      final cached = _storage.getConversations(me);
      final name = cached?.conversations[senderId]?.displayName;
      if (name != null && name.isNotEmpty) return name;
    }
    return 'New message';
  }

  String _messageTypeLabel(String messageType) {
    switch (messageType) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎤 Voice message';
      case 'document':
        return '📄 Document';
      default:
        return 'Sent you a message';
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _openConversation(Message message,
      {required bool isGroup}) async {
    final navigator = appNavigatorKey.currentState;
    final context = appNavigatorKey.currentContext;
    if (navigator == null || context == null) return;

    if (isGroup && message.groupId != null) {
      final group = await _resolveGroup(message.groupId!);
      navigator.push(
        MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
      );
      return;
    }

    final name = _resolveSenderName(message.senderId);
    navigator.push(MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: context.read<ChatBloc>(),
        child: ChatScreen(
          user: User(
            id: message.senderId,
            displayName: name == 'New message' ? null : name,
          ),
        ),
      ),
    ));
  }

  Future<Group> _resolveGroup(String groupId) async {
    try {
      final data = await ApiClient().getGroup(groupId);
      return Group.fromJson((data['group'] ?? data) as Map<String, dynamic>);
    } catch (_) {
      // Fall back to a skeleton; GroupChatScreen re-fetches members and
      // messages itself.
      return Group(
        id: groupId,
        name: 'Group',
        creatorId: '',
        memberIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  void _onTapPayload(NotificationPayload payload) {
    if (payload.senderId == null) return;
    final data = payload.data ?? const {};
    final isGroup = data['is_group'] == true || data['group_id'] != null;
    _openConversation(
      Message(
        id: (data['message_id'] as String?) ?? '',
        senderId: payload.senderId!,
        receiverId: '',
        groupId: data['group_id'] as String?,
        messageType: 'text',
        content: '',
        status: 'sent',
        createdAt: DateTime.now(),
      ),
      isGroup: isGroup,
    );
  }

  // ---------------------------------------------------------------------------
  // Banner overlay
  // ---------------------------------------------------------------------------

  void _showBanner({
    required String title,
    required String body,
    required VoidCallback onOpen,
  }) {
    _dismissBanner();

    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (overlayContext) {
        final topInset = MediaQuery.of(overlayContext).padding.top;
        return Positioned(
          top: topInset + 8,
          left: 12,
          right: 12,
          child: _NotificationBannerCard(
            title: title,
            body: body,
            onOpen: () {
              _dismissBanner();
              onOpen();
            },
            onExpired: _dismissBanner,
          ),
        );
      },
    );

    overlay.insert(entry);
    _activeBanner = entry;
  }

  void _dismissBanner() {
    final entry = _activeBanner;
    _activeBanner = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  void dispose() {
    _dismissBanner();
    _messageSub?.cancel();
    _groupMessageSub?.cancel();
    _notificationTapSub?.cancel();
    _decryptedMessageController.close();
    _decryptedGroupMessageController.close();
    WidgetsBinding.instance.removeObserver(this);
  }
}

class _NotificationBannerCard extends StatefulWidget {
  const _NotificationBannerCard({
    required this.title,
    required this.body,
    required this.onOpen,
    required this.onExpired,
  });

  final String title;
  final String body;
  final VoidCallback onOpen;
  final VoidCallback onExpired;

  @override
  State<_NotificationBannerCard> createState() =>
      _NotificationBannerCardState();
}

class _NotificationBannerCardState extends State<_NotificationBannerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _autoDismissTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) _collapse();
    });
  }

  Future<void> _collapse() async {
    _autoDismissTimer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onExpired();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _controller,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => unawaited(_collapse().then((_) => widget.onOpen())),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
