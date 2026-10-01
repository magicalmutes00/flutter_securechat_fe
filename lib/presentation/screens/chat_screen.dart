import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/time_format.dart';
import '../../data/models/message_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/in_app_notification_service.dart';
import '../../data/services/rtc/call_manager.dart';
import '../../data/services/websocket_service.dart';
import '../blocs/chat/chat_bloc.dart';
import '../blocs/chat/chat_event.dart';
import '../blocs/chat/chat_state.dart';
import '../widgets/auth_image.dart';
import '../widgets/message_bubble.dart';
import '../widgets/security_code_sheet.dart';
import '../widgets/ui/ui.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final User user;

  const ChatScreen({super.key, required this.user});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, GlobalKey> _messageKeys = {};
  bool _isTyping = false;
  bool _nearBottom = true;
  int _lastMessageCount = 0;
  StreamSubscription? _blocSubscription;

  /// Message the composer is currently replying to (screen-local UI state;
  /// only its id travels on the wire).
  Message? _replyingTo;

  /// Message id briefly ringed after a quote-strip jump lands on it.
  String? _highlightedId;

  String get _chatTitle =>
      widget.user.displayName ??
      widget.user.email ??
      widget.user.phone ??
      'Unknown user';

  void _startCall({required bool isVideo}) {
    final name = _chatTitle;
    CallManager.instance.nameResolver = (peerId) => name;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          peerId: widget.user.id,
          peerName: name,
          isVideoCall: isVideo,
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MessageSearchSheet(
        peerUserId: widget.user.id,
        onSelect: _jumpToMessage,
      ),
    );
  }

  /// Scrolls the list so the tapped search result is visible.
  void _jumpToMessage(Message message) {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _messageKeys[message.id]?.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: AppDurations.medium,
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    InAppNotificationService.instance.setViewingChat(widget.user.id);
    context.read<ChatBloc>().add(ChatLoadMessages(userId: widget.user.id));
    _scrollController.addListener(_onScroll);
    // Smart autoscroll: follow new messages only when the user is already
    // near the latest (or sent them) — never yank the list while reading.
    _blocSubscription = context.read<ChatBloc>().stream.listen((state) {
      final count = state.messages.length;
      if (_lastMessageCount == 0) {
        _lastMessageCount = count;
        return;
      }
      if (count > _lastMessageCount && _scrollController.hasClients) {
        final newest = state.messages.last;
        final mine = newest.senderId != widget.user.id;
        if (mine || _nearBottom) {
          _scrollController.animateTo(
            0,
            duration: AppDurations.medium,
            curve: Curves.easeOut,
          );
        }
      }
      _lastMessageCount = count;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final near = _scrollController.offset < 120;
    if (near != _nearBottom) setState(() => _nearBottom = near);
  }

  @override
  void dispose() {
    InAppNotificationService.instance.setViewingChat(null);
    _messageController.dispose();
    _scrollController.dispose();
    _blocSubscription?.cancel();
    super.dispose();
  }

  /// Captures the composer's reply target for a send and clears the preview.
  String? _takeReplyTarget() {
    final id = _replyingTo?.id;
    if (_replyingTo != null) setState(() => _replyingTo = null);
    return id;
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    context.read<ChatBloc>().add(ChatSendTextMessage(
          receiverId: widget.user.id,
          content: _messageController.text.trim(),
          replyToId: _takeReplyTarget(),
        ));

    _messageController.clear();
  }

  void _onComposerChanged(String value) {
    if (value.isNotEmpty && !_isTyping) {
      _isTyping = true;
      context.read<ChatBloc>().add(ChatSendTypingStatus(
            receiverId: widget.user.id,
            isTyping: true,
          ));
    } else if (value.isEmpty && _isTyping) {
      _isTyping = false;
      context.read<ChatBloc>().add(ChatSendTypingStatus(
            receiverId: widget.user.id,
            isTyping: false,
          ));
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null && mounted) {
        context.read<ChatBloc>().add(ChatSendFileMessage(
              receiverId: widget.user.id,
              filePath: image.path,
              messageType: AppConstants.messageTypeImage,
              replyToId: _takeReplyTarget(),
            ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video =
          await _imagePicker.pickVideo(source: ImageSource.camera);
      if (video != null && mounted) {
        context.read<ChatBloc>().add(ChatSendFileMessage(
              receiverId: widget.user.id,
              filePath: video.path,
              messageType: AppConstants.messageTypeVideo,
              replyToId: _takeReplyTarget(),
            ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking video: $e')),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && mounted) {
        final file = result.files.first;
        if (file.path != null) {
          context.read<ChatBloc>().add(ChatSendFileMessage(
                receiverId: widget.user.id,
                filePath: file.path!,
                messageType: AppConstants.messageTypeDocument,
                replyToId: _takeReplyTarget(),
              ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking document: $e')),
        );
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SheetScaffold(
        title: 'Share',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(context);
                _pickDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AppAvatar(
              label: _chatTitle,
              radius: 18,
              image: widget.user.avatarUrl != null
                  ? AuthImage(
                      path: widget.user.avatarUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorIcon: Icons.person,
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_chatTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  BlocBuilder<ChatBloc, ChatState>(
                    builder: (context, state) {
                      if (state.isTyping) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TypingDots(
                                color:
                                    context.appColors.typingIndicator),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'typing',
                              style: context.text.bodySmall?.copyWith(
                                color:
                                    context.appColors.typingIndicator,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        );
                      }
                      final online = widget.user.isOnline;
                      return Text(
                        online ? 'online' : 'offline',
                        style: context.text.bodySmall?.copyWith(
                          color: online
                              ? context.appColors.presenceOnline
                              : context.appColors.presenceOffline,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Voice call',
            onPressed: () => _startCall(isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Video call',
            onPressed: () => _startCall(isVideo: true),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search in conversation',
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'View safety number',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) =>
                    SecurityCodeSheet(peerUserId: widget.user.id),
              );
            },
          ),
        ],
      ),
      body: BlocListener<ChatBloc, ChatState>(
        listenWhen: (prev, curr) =>
            curr.errorMessage != null &&
            prev.errorMessage != curr.errorMessage,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage!)),
          );
        },
        child: Column(
          children: [
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state.status == ChatStatus.loading &&
                      state.messages.isEmpty) {
                    return const _BubbleSkeleton();
                  }

                  if (state.status == ChatStatus.error) {
                    return ErrorState(
                      message: state.errorMessage ??
                          'Failed to load messages',
                      onRetry: () => context.read<ChatBloc>().add(
                          ChatLoadMessages(userId: widget.user.id)),
                    );
                  }

                  if (state.messages.isEmpty) {
                    return EmptyState(
                      icon: Icons.waving_hand_outlined,
                      title: 'No messages yet',
                      body:
                          'Say hello to $_chatTitle — messages are end-to-end encrypted.',
                    );
                  }

                  return ListView(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    children: _buildMessageWidgets(state.messages),
                  );
                },
              ),
            ),
            ChatInputBar(
              controller: _messageController,
              onSend: _sendMessage,
              onAttach: _showAttachmentOptions,
              onChanged: _onComposerChanged,
              header: _replyingTo == null ? null : _buildReplyPreview(),
            ),
          ],
        ),
      ),
      floatingActionButton: _nearBottom
          ? null
          : FloatingActionButton.small(
              heroTag: 'scroll_latest',
              onPressed: () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: AppDurations.medium,
                    curve: Curves.easeOut,
                  );
                }
              },
              child: const Icon(Icons.arrow_downward),
            ),
    );
  }

  /// Quote preview above the composer for the message being replied to.
  Widget _buildReplyPreview() {
    final target = _replyingTo!;
    final me = WebSocketService().currentUserId;
    final snippet = ReplySnippet.forMessage(target);
    return QuoteStrip(
      senderName: target.senderId == me ? 'You' : _chatTitle,
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

  /// Builds oldest→newest widgets with day dividers and tight grouping for
  /// consecutive same-sender messages, then reverses for the `reverse` list.
  List<Widget> _buildMessageWidgets(List<Message> messages) {
    // Drop lookup keys for messages that are gone (deleted / refreshed).
    final ids = messages.map((m) => m.id).toSet();
    _messageKeys.removeWhere((id, _) => !ids.contains(id));

    // Resolve reply targets from the already-decrypted messages in state —
    // never re-fetch (a Signal ciphertext can only be decrypted once).
    final byId = {for (final m in messages) m.id: m};
    final me = WebSocketService().currentUserId;

    final widgets = <Widget>[];
    DateTime? lastDay;
    String? lastSender;
    for (final message in messages) {
      final created = message.createdAt;
      final day = DateTime(created.year, created.month, created.day);
      if (lastDay == null || day != lastDay) {
        widgets.add(_DayDivider(day: day));
        lastDay = day;
        lastSender = null;
      }
      final tight = lastSender == message.senderId;
      lastSender = message.senderId;
      final quoted =
          message.replyToId == null ? null : byId[message.replyToId];
      widgets.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: tight ? 0 : 3),
          child: Container(
            key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
            child: MessageBubble(
              message: message,
              isMe: message.senderId != widget.user.id,
              onDelete: () => context.read<ChatBloc>().add(
                    ChatDeleteMessage(
                      messageId: message.id,
                      otherUserId: widget.user.id,
                    ),
                  ),
              onReply: () => setState(() => _replyingTo = message),
              quotedMessage: quoted,
              quotedSenderName: quoted == null
                  ? null
                  : (quoted.senderId == me ? 'You' : _chatTitle),
              onTapQuote:
                  quoted == null ? null : () => _jumpToQuoted(quoted.id),
              isHighlighted: _highlightedId == message.id,
            ),
          ),
        ),
      );
    }
    return widgets.reversed.toList();
  }
}

class _DayDivider extends StatelessWidget {
  final DateTime day;

  const _DayDivider({required this.day});

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

/// Animated three-dot typing indicator in the app-bar subtitle.
class _TypingDots extends StatefulWidget {
  final Color color;

  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TypingDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) setState(() {});
  }

  Widget _dot(double start, double end) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: Curves.easeInOut),
        ),
      ),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(0.0, 0.4),
        const SizedBox(width: 3),
        _dot(0.3, 0.7),
        const SizedBox(width: 3),
        _dot(0.6, 1.0),
      ],
    );
  }
}

class _BubbleSkeleton extends StatelessWidget {
  const _BubbleSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      children: const [
        Align(
          alignment: Alignment.centerRight,
          child: SkeletonBox(width: 220, height: 52, radius: AppRadius.lg),
        ),
        SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: SkeletonBox(width: 180, height: 52, radius: AppRadius.lg),
        ),
        SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: SkeletonBox(width: 140, height: 44, radius: AppRadius.lg),
        ),
        SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: SkeletonBox(width: 240, height: 60, radius: AppRadius.lg),
        ),
      ],
    );
  }
}

class _MessageSearchSheet extends StatefulWidget {
  final String peerUserId;
  final void Function(Message message) onSelect;

  const _MessageSearchSheet({required this.peerUserId, required this.onSelect});

  @override
  State<_MessageSearchSheet> createState() => _MessageSearchSheetState();
}

class _MessageSearchSheetState extends State<_MessageSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ApiClient _apiClient = ApiClient();
  List<Message> _results = [];
  bool _isSearching = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final raw = await _apiClient.searchMessages(trimmed);
      final matches = raw
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .where((m) =>
              m.senderId == widget.peerUserId ||
              m.receiverId == widget.peerUserId)
          .toList();
      if (!mounted) return;
      setState(() {
        _results = matches;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _error = 'Search failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SheetScaffold(
        title: 'Search in conversation',
        child: Column(
          children: [
            AppTextField(
              controller: _searchController,
              hintText: 'Search messages...',
              prefixIcon: const Icon(Icons.search),
              textInputAction: TextInputAction.search,
              onChanged: _runSearch,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ErrorState(
                          message: _error!,
                          onRetry: () =>
                              _runSearch(_searchController.text),
                        )
                      : _results.isEmpty
                          ? Center(
                              child: Text(
                                _searchController.text.trim().isEmpty
                                    ? 'Type to search in this conversation.'
                                    : 'No matching messages.',
                                style: context.text.bodyMedium?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final message = _results[index];
                                final isMe =
                                    message.senderId != widget.peerUserId;
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    message.isTextMessage
                                        ? Icons.chat_bubble_outline
                                        : Icons.attach_file_outlined,
                                    color:
                                        context.appColors.primaryEmphasis,
                                    size: 20,
                                  ),
                                  title: Text(
                                    message.content.isEmpty
                                        ? '[Media message]'
                                        : message.content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${isMe ? 'You' : 'Them'} · '
                                    '${formatChatTime(message.createdAt)}',
                                  ),
                                  onTap: () => widget.onSelect(message),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
