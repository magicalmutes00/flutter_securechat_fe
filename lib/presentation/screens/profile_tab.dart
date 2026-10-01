import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/services/contacts_sync_service.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/auth/auth_event.dart';
import '../blocs/auth/auth_state.dart';
import '../blocs/chat/chat_bloc.dart';
import '../blocs/chat/chat_event.dart';
import '../blocs/theme/theme_cubit.dart';
import '../widgets/auth_image.dart';
import '../widgets/ui/ui.dart';

/// Profile tab: account header + editable identity, appearance, contact
/// sync, support rows and sign-out. Absorbs the old profile/settings pages.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  bool _isSyncingContacts = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    context
        .read<AuthBloc>()
        .add(AuthAvatarUploadRequested(filePath: picked.path));
  }

  Future<void> _editField({
    required String title,
    required String initial,
    required String hint,
    required void Function(String value) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: AppTextField(
            controller: controller,
            hintText: hint,
            autofocus: true,
            errorText: error,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              final value = controller.text.trim();
              if (value.isEmpty) {
                setDialogState(() => error = 'This field cannot be empty');
              } else {
                Navigator.pop(dialogContext, value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => error = 'This field cannot be empty');
                } else {
                  Navigator.pop(dialogContext, value);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty) onSave(result);
  }

  void _editName() {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    _editField(
      title: 'Display name',
      initial: user.displayName ?? '',
      hint: 'Your name',
      onSave: (value) => context
          .read<AuthBloc>()
          .add(AuthProfileUpdateRequested(displayName: value)),
    );
  }

  void _editUsername() {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    _editField(
      title: 'Username',
      initial: user.username ?? '',
      hint: 'username',
      onSave: (value) => context
          .read<AuthBloc>()
          .add(AuthProfileUpdateRequested(username: value)),
    );
  }

  Future<void> _syncContacts() async {
    setState(() => _isSyncingContacts = true);
    try {
      final users = await ContactsSyncService().sync();
      if (!mounted) return;
      setState(() => _isSyncingContacts = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            users.isEmpty
                ? 'No contacts on SecureChat yet'
                : 'Found ${users.length} contacts on SecureChat',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSyncingContacts = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sync contacts: $e')),
      );
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'You will stop receiving messages on this device until you sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<ChatBloc>().add(ChatReset());
              context.read<AuthBloc>().add(AuthLogoutRequested());
            },
            child: Text('Log out',
                style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: BlocConsumer<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr.profileErrorMessage != null &&
            prev.profileErrorMessage != curr.profileErrorMessage,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(state.profileErrorMessage ?? 'An error occurred')),
          );
          // Clear so an identical follow-up error still trips the guard
          // above instead of being silently swallowed.
          context.read<AuthBloc>().add(const AuthClearProfileError());
        },
        builder: (context, state) {
          final user = state.user;
          final isSaving = state.isSavingProfile;
          if (user == null) {
            return const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Not signed in',
            );
          }

          final colors = context.colors;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
            children: [
              _ProfileHeaderCard(
                displayName: user.displayName ?? 'Set your name',
                subtitle: user.username != null
                    ? '@${user.username}'
                    : (user.phone ?? user.email ?? 'SecureChat account'),
                avatarUrl: user.avatarUrl,
                isSaving: isSaving,
                onAvatarTap: isSaving ? null : _pickAvatar,
              ),
              const _SectionHeader('Account'),
              _SettingsRow(
                icon: Icons.person_outline,
                title: 'Display name',
                subtitle: user.displayName ?? 'Set your name',
                onTap: isSaving ? null : _editName,
              ),
              _SettingsRow(
                icon: Icons.alternate_email,
                title: 'Username',
                subtitle: user.username != null
                    ? '@${user.username}'
                    : 'Set a username',
                onTap: isSaving ? null : _editUsername,
              ),
              if (user.phone != null)
                _SettingsRow(
                  icon: Icons.phone_outlined,
                  title: 'Phone',
                  subtitle: user.phone!,
                ),
              if (user.email != null)
                _SettingsRow(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: user.email!,
                ),
              if (isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const _SectionHeader('Appearance'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme', style: context.text.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Auto follows your system setting.',
                        style: context.text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      BlocBuilder<ThemeCubit, ThemeMode>(
                        builder: (context, mode) => ThemeModeSelector(
                          value: mode,
                          onChanged: (next) =>
                              context.read<ThemeCubit>().setMode(next),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Chats'),
              _SettingsRow(
                icon: Icons.contacts_outlined,
                title: 'Connect contacts',
                subtitle: 'Find friends already on SecureChat',
                trailing: _isSyncingContacts
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _isSyncingContacts ? null : _syncContacts,
              ),
              const _SectionHeader('Support'),
              const _SettingsRow(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Message and call alerts',
                enabled: false,
              ),
              const _SettingsRow(
                icon: Icons.lock_outline,
                title: 'Privacy',
                subtitle: 'Last seen, profile photo',
                enabled: false,
              ),
              const _SettingsRow(
                icon: Icons.security_outlined,
                title: 'Security',
                subtitle: 'Safety numbers and verification',
                enabled: false,
              ),
              const _SettingsRow(
                icon: Icons.storage_outlined,
                title: 'Storage',
                subtitle: 'Media and cache management',
                enabled: false,
              ),
              const _SettingsRow(
                icon: Icons.help_outline,
                title: 'Help',
                subtitle: 'FAQs and contact support',
                enabled: false,
              ),
              const _SectionHeader('About'),
              const _SettingsRow(
                icon: Icons.info_outline,
                title: 'SecureChat',
                subtitle: 'Version 1.0.0 · end-to-end encrypted',
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton.danger(
                label: 'Log out',
                icon: Icons.logout,
                onPressed: _confirmLogout,
              ),
            ],
          );
        },
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
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.lg, 4, AppSpacing.sm),
      child: Text(
        label,
        style: context.text.labelLarge
            ?.copyWith(color: context.colors.onSurfaceVariant),
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final String displayName;
  final String subtitle;
  final String? avatarUrl;
  final bool isSaving;
  final VoidCallback? onAvatarTap;

  const _ProfileHeaderCard({
    required this.displayName,
    required this.subtitle,
    this.avatarUrl,
    this.isSaving = false,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppAvatar(
                  label: displayName,
                  radius: 32,
                  image: avatarUrl != null
                      ? AuthImage(
                          path: avatarUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorIcon: Icons.person,
                        )
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Material(
                    color: colors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onAvatarTap,
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.photo_camera,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: context.text.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: context.text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveOnTap = enabled ? onTap : null;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: enabled
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            icon,
            color: enabled
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
            size: 22,
          ),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing ??
            (enabled
                ? (effectiveOnTap != null
                    ? Icon(Icons.chevron_right,
                        color: colors.onSurfaceVariant)
                    : null)
                : _SoonPill()),
        onTap: effectiveOnTap,
      ),
    );
  }
}

class _SoonPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Soon',
        style: context.text.labelSmall?.copyWith(
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
