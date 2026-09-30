import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/group_model.dart';
import '../../data/models/message_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/e2ee/e2ee_service.dart';
import '../../data/services/in_app_notification_service.dart';
import '../../data/services/websocket_service.dart';
import '../widgets/message_bubble.dart';

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
  bool _isTyping = false;
  Timer? _typingClearTimer;
  StreamSubscription? _messageSub;
  StreamSubscription? _typingSub;

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
    setState(() => _isLoading = true);
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
        decrypted.add(await _decryptGroupMessage(m));
      }

      if (!mounted) return;
      setState(() {
        _messages = decrypted;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
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
      setState(() => _isTyping = isTyping);
      if (isTyping) {
        _typingClearTimer?.cancel();
        _typingClearTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _isTyping = false);
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
        _messages.add(message);
      }
      _scrollToBottom();
    });
  }

  Future<Message> _decryptGroupMessage(Message message) async {
    if (message.encryption != 'sgkey' ||
        message.cipherBody == null ||
        message.groupId == null) {
      return message;
    }
    try {
      final plaintext = await E2eeService.instance.decryptGroupText(
        currentUserId: _currentUserId ?? '',
        groupId: message.groupId!,
        senderId: message.senderId,
        cipherBody: message.cipherBody!,
        distributionB64: message.distribution,
      );
      return message.copyWith(
        content: plaintext,
        encryption: 'none',
        cipherBody: null,
        cipherType: null,
        distribution: null,
      );
    } catch (e) {
      return message.copyWith(
        content: '🔒 Unable to decrypt message',
        encryption: 'none',
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _currentUserId == null) return;
    _messageController.clear();

    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _currentUserId!,
      receiverId: widget.group.id,
      groupId: widget.group.id,
      messageType: 'text',
      content: content,
      status: 'sent',
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(tempMessage));

    Map<String, dynamic> crypto;
    try {
      crypto = await E2eeService.instance.prepareOutgoingGroupText(
        currentUserId: _currentUserId!,
        groupId: widget.group.id,
        plaintext: content,
      );
    } on E2eeEncryptionException catch (e) {
      // Encryption failed: nothing was sent. Remove the optimistic bubble
      // and explain why instead of silently sending plaintext.
      if (!mounted) return;
      setState(() => _messages.remove(tempMessage));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    }
    final usesSignal = crypto['encryption'] == 'sgkey';

    _wsService.sendGroupMessage(
      groupId: widget.group.id,
      messageType: 'text',
      content: usesSignal ? '' : content,
      encryption: crypto['encryption'] as String? ?? 'none',
      cipherType: crypto['cipher_type'] as int?,
      cipherBody: crypto['cipher_body'] as String?,
      distribution: crypto['distribution'] as String?,
    );
  }

  void _onTypingChanged(String value) {
    if (value.isNotEmpty && !_isTyping) {
      setState(() => _isTyping = true);
      _wsService.sendGroupTyping(widget.group.id, true);
    } else if (value.isEmpty && _isTyping) {
      setState(() => _isTyping = false);
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

  @override
  Widget build(BuildContext context) {
    final memberNames = _members
        .where((m) => m.id != _currentUserId)
        .map((m) => m.displayName ?? m.phone ?? m.email ?? 'Unknown')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.group.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              _isTyping
                  ? 'typing...'
                  : '${_members.length} members${memberNames.isNotEmpty ? ' · ${memberNames.take(3).join(', ')}${memberNames.length > 3 ? '...' : ''}' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.onlineStatusColor,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet. Say hi!',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message.senderId == _currentUserId;
                          final sender = _members
                              .where((m) => m.id == message.senderId)
                              .toList();
                          return Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!isMe && sender.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8, bottom: 2),
                                  child: Text(
                                    sender.first.displayName ??
                                        sender.first.phone ??
                                        'Unknown',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              MessageBubble(
                                message: message,
                                isMe: isMe,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, color: AppTheme.primaryColor),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onTypingChanged,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AppTheme.primaryColor,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
