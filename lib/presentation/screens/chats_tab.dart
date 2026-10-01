import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/time_format.dart';
import '../../data/models/group_model.dart';
import '../../data/models/message_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_client.dart';
import '../blocs/chat/chat_bloc.dart';
import '../blocs/chat/chat_event.dart';
import '../blocs/chat/chat_state.dart';
import '../widgets/auth_image.dart';
import '../widgets/ui/ui.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'new_group_screen.dart';

/// Chats tab: searchable conversation list, compact groups strip,
/// single "New chat" action. All visuals come from the theme.
class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  List<Group> _groups = [];
  bool _isSearching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final raw = await _apiClient.getGroups();
      if (!mounted) return;
      setState(() => _groups =
          raw.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList());
    } catch (_) {
      // Groups self-correct on the next visit.
    }
  }

  Future<void> _refresh() async {
    context.read<ChatBloc>().add(ChatLoadConversations());
    await _loadGroups();
  }

  void _openChat(User user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<ChatBloc>(),
          child: ChatScreen(user: user),
        ),
      ),
    );
  }

  void _openGroup(Group group) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
    );
  }

  void _showNewConversationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<ChatBloc>(),
        child: _NewConversationSheet(
          onUserSelected: (user) {
            Navigator.pop(sheetContext);
            _openChat(user);
          },
          onNewGroup: () {
            Navigator.pop(sheetContext);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewGroupScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search chats',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              )
            : const Text('SecureChat'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: 'Search',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                _query = '';
                _searchController.clear();
              });
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Column(
          children: [
            if (_groups.isNotEmpty && !_isSearching) _buildGroupsStrip(),
            Expanded(child: _buildConversationList()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_chat',
        onPressed: _showNewConversationSheet,
        icon: const Icon(Icons.add),
        label: const Text('New chat'),
      ),
    );
  }

  Widget _buildGroupsStrip() {
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
          child: Text(
            'Groups · ${_groups.length}',
            style: text.labelLarge
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final group = _groups[index];
              return InkWell(
                onTap: () => _openGroup(group),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  width: 72,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppAvatar(label: group.name, radius: 22),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        group.name,
                        style: text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildConversationList() {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        if (state.conversations.isNotEmpty) {
          final users = state.conversations.values.where((user) {
            if (_query.isEmpty) return true;
            final label =
                (user.displayName ?? user.email ?? user.phone ?? '')
                    .toLowerCase();
            return label.contains(_query);
          }).toList();

          if (users.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off_outlined,
              title: 'No matches',
              body: 'Try a different name, email or phone number.',
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return _ConversationTile(
                user: user,
                lastMessage: state.lastMessages[user.id],
                unreadCount: state.unreadCounts[user.id] ?? 0,
                onTap: () => _openChat(user),
              );
            },
          );
        }

        if (state.status == ChatStatus.loading) {
          return const SkeletonList();
        }

        if (state.status == ChatStatus.error) {
          return ErrorState(
            message: state.errorMessage ?? 'Failed to load conversations',
            onRetry: () =>
                context.read<ChatBloc>().add(ChatLoadConversations()),
          );
        }

        return EmptyState(
          icon: Icons.chat_bubble_outline,
          title: 'No conversations yet',
          body: 'Find a friend and start your first chat.',
          actionLabel: 'Start a chat',
          onAction: _showNewConversationSheet,
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final User user;
  final Message? lastMessage;
  final int unreadCount;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.user,
    this.lastMessage,
    this.unreadCount = 0,
    required this.onTap,
  });

  String get _displayLabel =>
      user.displayName ?? user.email ?? user.phone ?? 'Unknown user';

  (IconData?, String) get _preview {
    final message = lastMessage;
    if (message == null) {
      return (
        null,
        user.isOnline ? 'Online — say hello' : 'Tap to chat'
      );
    }
    if (message.isTextMessage) return (null, message.content);
    if (message.isImageMessage) return (Icons.image_outlined, 'Photo');
    if (message.isVideoMessage) return (Icons.videocam_outlined, 'Video');
    if (message.isAudioMessage) return (Icons.mic_outlined, 'Voice message');
    if (message.isDocumentMessage) {
      return (Icons.insert_drive_file_outlined, 'Document');
    }
    return (null, message.content);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final hasUnread = unreadCount > 0;
    final (previewIcon, previewText) = _preview;

    return ListTile(
      onTap: onTap,
      leading: AppAvatar(
        label: _displayLabel,
        radius: 26,
        isOnline: user.isOnline,
        image: user.avatarUrl != null
            ? AuthImage(
                path: user.avatarUrl!,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorIcon: Icons.person,
              )
            : null,
      ),
      title: Text(
        _displayLabel,
        style: text.titleMedium?.copyWith(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (previewIcon != null) ...[
            Icon(previewIcon, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              previewText,
              style: text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight:
                    hasUnread ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: SizedBox(
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (lastMessage != null)
              Text(
                formatChatTime(lastMessage!.createdAt),
                style: text.labelSmall?.copyWith(
                  color: hasUnread
                      ? context.appColors.primaryEmphasis
                      : colors.onSurfaceVariant,
                  fontWeight:
                      hasUnread ? FontWeight.w700 : FontWeight.w500,
                ),
              )
            else if (user.lastSeen != null)
              Text(
                formatChatTime(user.lastSeen!),
                style: text.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            if (hasUnread) ...[
              const SizedBox(height: AppSpacing.xs),
              UnreadBadge(count: unreadCount),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewConversationSheet extends StatefulWidget {
  final void Function(User user) onUserSelected;
  final VoidCallback onNewGroup;

  const _NewConversationSheet({
    required this.onUserSelected,
    required this.onNewGroup,
  });

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SheetScaffold(
          title: 'New chat',
          child: Column(
            children: [
              AppTextField(
                controller: _searchController,
                hintText: 'Search by phone or email...',
                prefixIcon: const Icon(Icons.search),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                onChanged: (query) =>
                    context.read<ChatBloc>().add(ChatSearchUsers(query)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: BlocBuilder<ChatBloc, ChatState>(
                  builder: (context, state) {
                    if (state.isSearching) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: state.searchResults.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            leading: const AppAvatar(
                                label: 'New group', radius: 22),
                            title: const Text('New group'),
                            subtitle: const Text('Chat with several people'),
                            trailing: const Icon(Icons.group_add_outlined),
                            onTap: widget.onNewGroup,
                          );
                        }
                        final user = state.searchResults[index - 1];
                        final label = user.displayName ??
                            user.email ??
                            user.phone ??
                            'No name';
                        return ListTile(
                          leading: AppAvatar(label: label, radius: 22),
                          title: Text(label),
                          subtitle:
                              Text(user.email ?? user.phone ?? ''),
                          onTap: () => widget.onUserSelected(user),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
