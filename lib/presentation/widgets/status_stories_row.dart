import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/status_model.dart';
import '../../data/models/user_model.dart';

/// Horizontal row of status "stories" with the user's own status first, mirroring
/// the WhatsApp Status tab. Each entry is a circular avatar with a colored ring.
class StatusStoriesRow extends StatelessWidget {
  const StatusStoriesRow({
    super.key,
    required this.myStatuses,
    required this.statusesByUser,
    required this.currentUserId,
    required this.onCreatePressed,
    required this.onStatusTap,
  });

  /// Statuses posted by the current user (newest first).
  final List<Status> myStatuses;

  /// Map of contact user id -> that user's active statuses (newest first).
  final Map<String, List<Status>> statusesByUser;

  final String currentUserId;
  final VoidCallback onCreatePressed;
  final void Function(User user, List<Status> statuses) onStatusTap;

  bool _hasUnviewed(List<Status> statuses) =>
      statuses.any((s) => !s.hasBeenViewedBy(currentUserId));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _MyStatusEntry(
            hasStatus: myStatuses.isNotEmpty,
            onTap: onCreatePressed,
          ),
          for (final entry in statusesByUser.entries)
            _StatusEntry(
              user: entry.value.first.author ??
                  User(id: entry.key, displayName: 'Unknown'),
              statuses: entry.value,
              unviewed: _hasUnviewed(entry.value),
              onTap: () => onStatusTap(
                  entry.value.first.author ??
                      User(id: entry.key, displayName: 'Unknown'),
                  entry.value),
            ),
        ],
      ),
    );
  }
}

class _MyStatusEntry extends StatelessWidget {
  final bool hasStatus;
  final VoidCallback onTap;

  const _MyStatusEntry({required this.hasStatus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      hasStatus ? AppTheme.primaryColor : Colors.grey[300],
                  child: hasStatus
                      ? const Icon(Icons.person, color: Colors.white, size: 30)
                      : const Icon(Icons.person, color: Colors.grey, size: 30),
                ),
                if (!hasStatus)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'My status',
              style: TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusEntry extends StatelessWidget {
  final User user;
  final List<Status> statuses;
  final bool unviewed;
  final VoidCallback onTap;

  const _StatusEntry({
    required this.user,
    required this.statuses,
    required this.unviewed,
    required this.onTap,
  });

  String get _label =>
      user.displayName ?? user.email ?? user.phone ?? 'Unknown';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: unviewed ? AppTheme.primaryColor : Colors.grey[400]!,
                  width: 2.5,
                ),
              ),
              child: CircleAvatar(
                radius: 21,
                backgroundColor: AppTheme.primaryColor,
                child: _label.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 26)
                    : Text(
                        _label[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _label,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
