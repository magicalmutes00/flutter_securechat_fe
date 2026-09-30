import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/time_format.dart';
import '../../data/models/status_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/websocket_service.dart';
import '../widgets/ui/ui.dart';
import 'create_status_screen.dart';
import 'story_viewer_screen.dart';

/// Status tab: the user's own status plus everyone else's updates,
/// split into recent and viewed sections.
class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  final ApiClient _apiClient = ApiClient();
  List<Status> _myStatuses = [];
  Map<String, List<Status>> _statusesByUser = {};
  String _currentUserId = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
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
      final me = WebSocketService().currentUserId ?? '';
      final grouped = <String, List<Status>>{};
      for (final s in statuses) {
        if (s.userId == me) continue;
        grouped.putIfAbsent(s.userId, () => []).add(s);
      }
      setState(() {
        _currentUserId = me;
        _myStatuses = statuses.where((s) => s.userId == me).toList();
        _statusesByUser = grouped;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
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

  bool _hasUnviewed(List<Status> statuses) =>
      statuses.any((s) => !s.hasBeenViewedBy(_currentUserId));

  @override
  Widget build(BuildContext context) {
    final recent = <String, List<Status>>{};
    final viewed = <String, List<Status>>{};
    for (final entry in _statusesByUser.entries) {
      if (_hasUnviewed(entry.value)) {
        recent[entry.key] = entry.value;
      } else {
        viewed[entry.key] = entry.value;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add status',
            onPressed: _openCreateStatus,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStatuses,
        child: _isLoading
            ? const SkeletonList()
            : _myStatuses.isEmpty && _statusesByUser.isEmpty
                ? EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: 'No updates yet',
                    body:
                        'Share a photo or a thought — it disappears after 24 hours.',
                    actionLabel: 'Add status',
                    onAction: _openCreateStatus,
                  )
                : ListView(
                    children: [
                      _MyStatusCard(
                        hasStatus: _myStatuses.isNotEmpty,
                        latestAt: _myStatuses.isNotEmpty
                            ? _myStatuses.first.createdAt
                            : null,
                        onView: _myStatuses.isEmpty
                            ? null
                            : () => _openStoryViewer(
                                  _myStatuses.first.author ??
                                      User(
                                          id: _currentUserId,
                                          displayName: 'You'),
                                  _myStatuses,
                                ),
                        onCreate: _openCreateStatus,
                      ),
                      if (recent.isNotEmpty) ...[
                        _SectionHeader(
                            'Recent updates · ${recent.length}'),
                        for (final entry in recent.entries)
                          _StatusTile(
                            user: entry.value.first.author ??
                                User(
                                    id: entry.key,
                                    displayName: 'Unknown'),
                            statuses: entry.value,
                            unviewed: true,
                            onTap: () => _openStoryViewer(
                              entry.value.first.author ??
                                  User(
                                      id: entry.key,
                                      displayName: 'Unknown'),
                              entry.value,
                            ),
                          ),
                      ],
                      if (viewed.isNotEmpty) ...[
                        const _SectionHeader('Viewed updates'),
                        for (final entry in viewed.entries)
                          _StatusTile(
                            user: entry.value.first.author ??
                                User(
                                    id: entry.key,
                                    displayName: 'Unknown'),
                            statuses: entry.value,
                            unviewed: false,
                            onTap: () => _openStoryViewer(
                              entry.value.first.author ??
                                  User(
                                      id: entry.key,
                                      displayName: 'Unknown'),
                              entry.value,
                            ),
                          ),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Text(
        label,
        style: context.text.labelLarge
            ?.copyWith(color: context.colors.onSurfaceVariant),
      ),
    );
  }
}

class _MyStatusCard extends StatelessWidget {
  final bool hasStatus;
  final DateTime? latestAt;
  final VoidCallback? onView;
  final VoidCallback onCreate;

  const _MyStatusCard({
    required this.hasStatus,
    this.latestAt,
    this.onView,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Card(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const AppAvatar(label: 'You', radius: 26),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Icon(Icons.add,
                    size: 16, color: colors.onSecondary),
              ),
            ),
          ],
        ),
        title: const Text('My status'),
        subtitle: Text(
          hasStatus && latestAt != null
              ? formatChatTime(latestAt!)
              : 'Tap to add a status update',
          style: text.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        trailing: hasStatus
            ? null
            : Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        onTap: hasStatus ? onView : onCreate,
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final User user;
  final List<Status> statuses;
  final bool unviewed;
  final VoidCallback onTap;

  const _StatusTile({
    required this.user,
    required this.statuses,
    required this.unviewed,
    required this.onTap,
  });

  String get _label =>
      user.displayName ?? user.email ?? user.phone ?? 'Unknown';

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: unviewed ? appColors.storyRing : appColors.storyRingSeen,
            width: 2.5,
          ),
        ),
        child: AppAvatar(label: _label, radius: 22),
      ),
      title: Text(_label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${statuses.length} update${statuses.length == 1 ? '' : 's'} · ${formatChatTime(statuses.first.createdAt)}',
        style: context.text.bodyMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontWeight: unviewed ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
