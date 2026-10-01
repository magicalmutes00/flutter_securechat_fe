import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/models/group_model.dart';
import '../../data/models/message_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/e2ee/e2ee_service.dart';
import '../../data/services/in_app_notification_service.dart';
import '../../data/services/websocket_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/ui/ui.dart';

class GroupChatScreen extends StatefulWidget {
  final Group group;
  final List<User> members;

  const GroupChatScreen({
    super.key,
    required this.group,
    this.members = const [],
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final ApiClient _apiClient = ApiClient();
  final WebSocketService _wsService = WebSocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  List<User> _members = [];
  bool _isLoading = true;
  bool _loadError = false;
  bool _peerTyping = false;
  bool _typingActive = false;
  Timer? _typingClearTimer;
  StreamSubscription? _messageSub;
  StreamSubscription? _typingSub;

  /// Message the composer is currently replying to (screen-local UI state;
  /// only its id travels on the wire).
  Message? _replyingTo;

  /// Message id briefly ringed after a quote-strip jump lands on it.
  String? _highlightedId;
  final Map<String, GlobalKey> _messageKeys = {};

  String? get _currentUserId => _wsService.currentUserId;

  @override
  void initState() {
    super.initState();
    InAppNotificationService.instance.setViewingChat(widget.group.id);
    _members = List.from(widget.members);
    _loadMessages();
    _subscribe();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _loadError = false;
    });
    try {
      if (_members.isEmpty) {
        final groupData = await _apiClient.getGroup(widget.group.id);
        final rawMembers = groupData['members'] as List<dynamic>? ?? [];
        final resolvedMembers = rawMembers
            .map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList();
        _members = resolvedMembers;
      }

      final raw =
          await _apiClient.getGroupMessages(widget.group.id, limit: 100);
      final fetched = raw
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();

      final decrypted = <Message>[];
      for (final m in fetched) {
        decrypted.add(_asDisplayable(await _decryptGroupMessage(m)));
      }

      if (!mounted) return;
      setState(() {
        _messages = decrypted;
        _isLoading = false;
      });
      _jumpToLatest();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = _messages.isEmpty;
      });
    }
  }

  void _subscribe() {
    // Live messages arrive already decrypted by InAppNotificationService
    // (each sender-key ciphertext must be decrypted exactly once).
    _messageSub = InAppNotificationService.instance.decryptedGroupMessageStream
        .listen((message) {
      if (message.groupId != widget.group.id) return;
      unawaited(_onIncoming(message));
    });
    _typingSub = _wsService.groupTypingStream.listen((data) {
      if (data['group_id'] != widget.group.id) return;
      final isTyping = data['is_typing'] as bool? ?? false;
      setState(() => _peerTyping = isTyping);
      if (isTyping) {
        _typingClearTimer?.cancel();
        _typingClearTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _peerTyping = false);
        });
      } else {
        _typingClearTimer?.cancel();
      }
    });
  }

  Future<void> _onIncoming(Message message) async {
    if (!mounted) return;
    if (message.senderId == _currentUserId) return;
    setState(() {
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.add(_asDisplayable(message));
      }
    });
    _scrollToLatest();
  }

  Future<Message> _decryptGroupMessage(Message message) async {
    // Memoized in E2eeService: live socket delivery and history fetches share
    // the first successful plaintext instead of consuming the sender-key
    // chain twice (which throws and renders the placeholder).
    return E2eeService.instance.decryptGroupMessage(
      message,
      currentUserId: _currentUserId ?? '',
    );
  }

  /// Plaintext-era group messages carry no ciphertext; anything else that
  /// still arrives undecryptable gets an honest notice bubble.
  Message _asDisplayable(Message m) {
    if (m.content.isEmpty &&
        (m.encryption == 'signal' || m.encryption == 'sgkey')) {
      return m.copyWith(
        content: '🔒 Encrypted message from before encryption was removed',
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
      );
    }
    return m;
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppDurations.medium,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _currentUserId == null) return;
    _messageController.clear();
    final replyTarget = _replyingTo;
    if (replyTarget != null) setState(() => _replyingTo = null);
    await _sendGroupContent(content, replyTarget);
  }

  /// Re-runs the group send pipeline for a failed bubble. The failed attempt
  /// is dropped and a fresh optimistic bubble starts — nothing is replayed.
  Future<void> _retryGroupMessage(Message failed) async {
    if (failed.senderId != _currentUserId) return;
    setState(() => _messages.removeWhere((m) => m.id == failed.id));
    Message? target;
    if (failed.replyToId != null) {
      for (final m in _messages) {
        if (m.id == failed.replyToId) {
          target = m;
          break;
        }
      }
    }
    await _sendGroupContent(failed.content, target);
  }

  Future<void> _sendGroupContent(String content, Message? replyTarget) async {
    final me = _currentUserId;
    if (me == null) return;

    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      senderId: me,
      receiverId: widget.group.id,
      replyToId: replyTarget?.id,
      groupId: widget.group.id,
      messageType: 'text',
      content: content,
      status: 'sending',
      createdAt: DateTime.now(),
    );
    if (!mounted) return;
    setState(() => _messages.add(tempMessage));
    _scrollToLatest();

    void markFailed(String reason) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempMessage.id);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(status: 'failed');
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(reason)));
    }

    Map<String, dynamic> crypto;
    try {
      crypto = await E2eeService.instance.prepareOutgoingGroupText(
        currentUserId: me,
        groupId: widget.group.id,
        plaintext: content,
      );
    } on E2eeEncryptionException catch (e) {
      // Encryption failed: nothing was sent. Remove the optimistic bubble
      // and explain why instead of silently sending plaintext.
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m.id == tempMessage.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not secure that message: ${e.message}')),
      );
      return;
    }
    final usesSignal = crypto['encryption'] == 'sgkey';

    // Groups have no ack path and no REST send: a dead socket must mark the
    // bubble failed (retryable) instead of leaving a phantom 'sent' bubble.
    const offlineReason = 'No connection — the message was not sent. '
        'Try again when you are back online.';
    if (!_wsService.isConnected) {
      markFailed(offlineReason);
      return;
    }
    try {
      // Temp ids are meaningless to the server (and this screen has no
      // ack/swap path to resolve them later), so a reply to a still-sending
      // bubble keeps its link locally only; the server row carries no link
      // in that race.
      final wireReplyId = replyTarget?.id;
      _wsService.sendGroupMessage(
        groupId: widget.group.id,
        messageType: 'text',
        content: usesSignal ? '' : content,
        replyToId: wireReplyId != null && wireReplyId.startsWith('temp_')
            ? null
            : wireReplyId,
        encryption: crypto['encryption'] as String? ?? 'none',
        cipherType: crypto['cipher_type'] as int?,
        cipherBody: crypto['cipher_body'] as String?,
        distribution: crypto['distribution'] as String?,
      );
    } catch (_) {
      // Socket died mid-send.
      markFailed(offlineReason);
      return;
    }

    if (!mounted) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == tempMessage.id);
      if (idx != -1) _messages[idx] = _messages[idx].copyWith(status: 'sent');
    });
  }

  void _onTypingChanged(String value) {
    // Composer typing state only drives the wire event, never the subtitle
    // (the subtitle reflects *other* members typing).
    if (value.isNotEmpty && !_typingActive) {
      _typingActive = true;
      _wsService.sendGroupTyping(widget.group.id, true);
    } else if (value.isEmpty && _typingActive) {
      _typingActive = false;
      _wsService.sendGroupTyping(widget.group.id, false);
    }
  }

  @override
  void dispose() {
    InAppNotificationService.instance.setViewingChat(null);
    _messageSub?.cancel();
    _typingSub?.cancel();
    _typingClearTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _senderLabel(String senderId) {
    if (senderId == _currentUserId) return 'You';
    for (final m in _members) {
      if (m.id == senderId) {
        return m.displayName ?? m.phone ?? m.email ?? 'Unknown';
      }
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final memberNames = _members
        .where((m) => m.id != _currentUserId)
        .map((m) => m.displayName ?? m.phone ?? m.email ?? 'Unknown')
        .toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AppAvatar(label: widget.group.name, radius: 18),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.group.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    _peerTyping
                        ? 'typing...'
                        : '${_members.length} member${_members.length == 1 ? '' : 's'}${memberNames.isNotEmpty ? ' · ${memberNames.take(3).join(', ')}${memberNames.length > 3 ? '…' : ''}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: _peerTyping
                          ? context.appColors.typingIndicator
                          : context.colors.onSurfaceVariant,
                      fontStyle:
                          _peerTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const SkeletonList(itemCount: 4)
                : _loadError
                    ? ErrorState(
                        message: 'Failed to load messages',
                        onRetry: _loadMessages,
                      )
                    : _messages.isEmpty
                        ? EmptyState(
                            icon: Icons.group_outlined,
                            title: 'No messages yet',
                            body:
                                'Say hello to ${widget.group.name} — group messages are end-to-end encrypted.',
                          )
                        : ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.sm),
                            children: _buildMessageWidgets(),
                          ),
          ),
          ChatInputBar(
            controller: _messageController,
            onSend: _sendMessage,
            onChanged: _onTypingChanged,
            header: _replyingTo == null ? null : _buildReplyPreview(),
          ),
        ],
      ),
    );
  }

  /// Quote preview above the composer for the message being replied to.
  Widget _buildReplyPreview() {
    final target = _replyingTo!;
    final snippet = ReplySnippet.forMessage(target);
    return QuoteStrip(
      senderName: _senderLabel(target.senderId),
      snippet: snippet.text,
      leadingIcon: snippet.icon,
      style: QuoteStripStyle(
        barColor: context.appColors.primaryEmphasis,
        nameColor: context.appColors.primaryEmphasis,
        snippetColor: context.colors.onSurfaceVariant,
      ),
      onClose: () => setState(() => _replyingTo = null),
    );
  }

  /// Scrolls the list to the quoted original and rings it briefly.
  void _jumpToQuoted(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _messageKeys[messageId]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: AppDurations.medium,
        curve: Curves.easeOut,
        alignment: 0.5,
      );
      setState(() => _highlightedId = messageId);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _highlightedId == messageId) {
          setState(() => _highlightedId = null);
        }
      });
    });
  }

  /// Oldest→newest with day dividers and tight same-sender grouping.
  /// (This list is *not* reversed, unlike the 1:1 chat.)
  List<Widget> _buildMessageWidgets() {
    // Drop lookup keys for messages that are gone (deleted / refreshed).
    final ids = _messages.map((m) => m.id).toSet();
    _messageKeys.removeWhere((id, _) => !ids.contains(id));

    // Resolve reply targets from the already-decrypted messages in state —
    // never re-fetch (a sender-key ciphertext can only be decrypted once).
    final byId = {for (final m in _messages) m.id: m};

    final widgets = <Widget>[];
    DateTime? lastDay;
    String? lastSender;
    for (final message in _messages) {
      final created = message.createdAt;
      final day = DateTime(created.year, created.month, created.day);
      if (lastDay == null || day != lastDay) {
        widgets.add(_GroupDayDivider(day: day));
        lastDay = day;
        lastSender = null;
      }
      final isMe = message.senderId == _currentUserId;
      final tight = lastSender == message.senderId;
      lastSender = message.senderId;
      final quoted =
          message.replyToId == null ? null : byId[message.replyToId];
      widgets.add(
        Padding(
          key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
          padding: EdgeInsets.symmetric(vertical: tight ? 0 : 3),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe && !tight)
                Padding(
                  padding: const EdgeInsets.only(
                      left: AppSpacing.sm, bottom: AppSpacing.xs),
                  child: Text(
                    _senderLabel(message.senderId),
                    style: context.text.labelSmall?.copyWith(
                      color: context.appColors.primaryEmphasis,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              MessageBubble(
                message: message,
                isMe: isMe,
                onReply: () => setState(() => _replyingTo = message),
                quotedMessage: quoted,
                quotedSenderName:
                    quoted == null ? null : _senderLabel(quoted.senderId),
                onTapQuote:
                    quoted == null ? null : () => _jumpToQuoted(quoted.id),
                isHighlighted: _highlightedId == message.id,
                // Failed own-bubbles re-run the send pipeline on tap.
                onRetry: message.isFailed && isMe
                    ? () => _retryGroupMessage(message)
                    : null,
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }
}

class _GroupDayDivider extends StatelessWidget {
  final DateTime day;

  const _GroupDayDivider({required this.day});

  String _label(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(day);
    return DateFormat('MMM d, y').format(day);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            _label(DateTime.now()),
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
