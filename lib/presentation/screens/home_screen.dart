import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/group_model.dart';
import '../../data/models/message_model.dart';
import '../../data/models/status_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/push_notification_service.dart';
import '../../data/services/rtc/call_manager.dart';
import '../../data/services/websocket_service.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/auth/auth_event.dart';
import '../blocs/chat/chat_bloc.dart';
import '../blocs/chat/chat_event.dart';
import '../blocs/chat/chat_state.dart';
import '../widgets/status_stories_row.dart';
import 'chat_screen.dart';
import 'create_status_screen.dart';
import 'group_chat_screen.dart';
import 'login_screen.dart';
import 'new_group_screen.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'story_viewer_screen.dart';
import '../widgets/auth_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiClient _apiClient = ApiClient();
  List<Group> _groups = [];
  List<Status> _myStatuses = [];
  Map<String, List<Status>> _statusesByUser = {};
  String _currentUserId = '';

  @override
  void initState() {
    super.initState();
    context.read<ChatBloc>().add(ChatLoadConversations());
    _loadGroups();
    _initCalls();
    _initPush();
    _loadStatuses();
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

  Future<void> _loadStatuses() async {
    try {
      final raw = await _apiClient.getStatuses();
      final statuses = raw.map((e) {
        final map = e as Map<String, dynamic>;
        final status = Status.fromJson(map['status'] as Map<String, dynamic>);
        final author = map['author'] as Map<String, dynamic>?;
        return Status(
          id: status.id,
          userId: status.userId,
          text: status.text,
          mediaPath: status.mediaPath,
          mediaType: status.mediaType,
          createdAt: status.createdAt,
          expiresAt: status.expiresAt,
          viewers: status.viewers,
          author: author != null ? User.fromJson(author) : null,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _currentUserId = WebSocketService().currentUserId ?? '';
        _myStatuses =
            statuses.where((s) => s.userId == _currentUserId).toList();
        final grouped = <String, List<Status>>{};
        for (final s in statuses) {
          if (s.userId == _currentUserId) continue;
          grouped.putIfAbsent(s.userId, () => []).add(s);
        }
        _statusesByUser = grouped;
      });
    } catch (e) {
      // Statuses are best-effort; ignore failures.
    }
  }

  Future<void> _openCreateStatus() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
    );
    if (created == true) _loadStatuses();
  }

  void _openStoryViewer(User user, List<Status> statuses) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => StoryViewerScreen(
              user: user,
              statuses: statuses,
              currentUserId: _currentUserId,
            ),
          ),
        )
        .then((_) => _loadStatuses());
  }

  Future<void> _loadGroups() async {
    try {
      final raw = await _apiClient.getGroups();
      final groups =
          raw.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() => _groups = groups);
    } catch (e) {
      // Ignore; groups self-correct on the next visit.
    }
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
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(group: group),
      ),
    );
  }

  void _showNewConversationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<ChatBloc>(),
        child: _NewConversationSheet(
          onUserSelected: (user) {
            Navigator.pop(sheetContext);
            _openChat(user);
          },
        ),
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<ChatBloc>().add(ChatReset());
              context.read<AuthBloc>().add(AuthLogoutRequested());
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Logout',
                style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SecureChat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.grey),
                    SizedBox(width: 12),
                    Text('Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.grey),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: AppTheme.errorColor),
                    SizedBox(width: 12),
                    Text('Logout',
                        style: TextStyle(color: AppTheme.errorColor)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              } else if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          StatusStoriesRow(
            myStatuses: _myStatuses,
            statusesByUser: _statusesByUser,
            currentUserId: _currentUserId,
            onCreatePressed: _openCreateStatus,
            onStatusTap: _openStoryViewer,
          ),
          if (_groups.isNotEmpty)
            Container(
              height: 96,
              margin: const EdgeInsets.only(top: 4),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _groups.length,
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  return InkWell(
                    onTap: () => _openGroup(group),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppTheme.primaryColor,
                            child: Text(
                              group.name.isEmpty
                                  ? 'G'
                                  : group.name[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            group.name,
                            style: const TextStyle(fontSize: 12),
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
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                // Show conversations if we have them, even if there's an error
                if (state.conversations.isNotEmpty) {
                  return ListView.builder(
                    itemCount: state.conversations.length,
                    itemBuilder: (context, index) {
                      final user = state.conversations.values.elementAt(index);
                      final lastMessage = state.lastMessages[user.id];
                      return _ConversationTile(
                        user: user,
                        lastMessage: lastMessage,
                        onTap: () => _openChat(user),
                      );
                    },
                  );
                }

                // Only show loading/error if no conversations
                if (state.status == ChatStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.status == ChatStatus.error) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: Colors.red[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load conversations',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            context
                                .read<ChatBloc>()
                                .add(ChatLoadConversations());
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No conversations yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start a new chat!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'new_group',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewGroupScreen()),
              );
            },
            child: const Icon(Icons.group_add),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'new_chat',
            onPressed: _showNewConversationSheet,
            child: const Icon(Icons.message),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final User user;
  final Message? lastMessage;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.user,
    this.lastMessage,
    required this.onTap,
  });

  String get _displayLabel =>
      user.displayName ?? user.email ?? user.phone ?? 'Unknown user';

  String get _lastMessagePreview {
    if (lastMessage == null) return '';
    if (lastMessage!.isTextMessage) return lastMessage!.content;
    if (lastMessage!.isImageMessage) return '📷 Photo';
    if (lastMessage!.isVideoMessage) return '🎥 Video';
    if (lastMessage!.isAudioMessage) return '🎤 Voice message';
    if (lastMessage!.isDocumentMessage) return '📄 Document';
    return lastMessage!.content;
  }

  String get _lastMessageTime {
    if (lastMessage == null) return '';
    return DateFormat('HH:mm').format(lastMessage!.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.white,
        child: user.avatarUrl != null
            ? ClipOval(
                child: AuthImage(
                  path: user.avatarUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorIcon: Icons.person,
                ),
              )
            : const Icon(
                Icons.person,
                color: AppTheme.primaryColor,
              ),
      ),
      title: Text(
        _displayLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          if (user.isOnline)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                color: AppTheme.onlineStatusColor,
                shape: BoxShape.circle,
              ),
            ),
          Expanded(
            child: Text(
              lastMessage != null
                  ? _lastMessagePreview
                  : (user.isOnline ? 'online' : 'Tap to chat'),
              style: TextStyle(
                color: user.isOnline ? AppTheme.onlineStatusColor : Colors.grey,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMessage != null)
            Text(
              _lastMessageTime,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            )
          else if (user.isOnline)
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppTheme.onlineStatusColor,
                shape: BoxShape.circle,
              ),
            )
          else
            Text(
              user.lastSeen != null
                  ? DateFormat('HH:mm').format(user.lastSeen!)
                  : '',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
        ],
      ),
    );
  }
}

class _NewConversationSheet extends StatefulWidget {
  final Function(User) onUserSelected;

  const _NewConversationSheet({required this.onUserSelected});

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

  void _onSearchChanged(String query) {
    context.read<ChatBloc>().add(ChatSearchUsers(query));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'New Conversation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by phone or email...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state.isSearching) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state.searchResults.isEmpty) {
                    return Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? 'Enter a phone number or email to search'
                            : 'No users found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: state.searchResults.length,
                    itemBuilder: (context, index) {
                      final user = state.searchResults[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryColor,
                          child: Text(
                            (user.displayName ??
                                    user.email ??
                                    user.phone ??
                                    'U')[0]
                                .toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(user.displayName ?? 'No name'),
                        subtitle: Text(user.email ?? user.phone ?? ''),
                        onTap: () => widget.onUserSelected(user),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
