import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/user_model.dart';

class ConversationList extends StatelessWidget {
  final Map<String, User> conversations;
  final Function(User) onConversationTap;

  const ConversationList({
    super.key,
    required this.conversations,
    required this.onConversationTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final user = conversations.values.elementAt(index);
        return _ConversationTile(
          user: user,
          onTap: () => onConversationTap(user),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final User user;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.user,
    required this.onTap,
  });

  String get _displayLabel =>
      user.displayName ?? user.email ?? user.phone ?? 'Unknown user';

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: user.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      user.avatarUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.person,
                    color: AppTheme.primaryColor,
                  ),
          ),
          if (user.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppTheme.onlineStatusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        _displayLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        user.isOnline ? 'online' : 'Tap to chat',
        style: TextStyle(
          color: user.isOnline ? AppTheme.onlineStatusColor : Colors.grey,
          fontSize: 13,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (user.isOnline)
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppTheme.onlineStatusColor,
                shape: BoxShape.circle,
              ),
            )
          else if (user.lastSeen != null)
            Text(
              DateFormat('HH:mm').format(user.lastSeen!),
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
