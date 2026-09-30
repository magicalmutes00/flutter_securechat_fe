import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/contacts_sync_service.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/auth/auth_state.dart';
import '../widgets/auth_image.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isSyncingContacts = false;

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
        SnackBar(
          content: Text('Failed to sync contacts: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state.user;
          return ListView(
            children: [
              if (user != null)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor,
                    child: user.avatarUrl != null
                        ? ClipOval(
                            child: AuthImage(
                              path: user.avatarUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorIcon: Icons.person,
                            ),
                          )
                        : const Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    user.displayName ?? 'Unknown user',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    user.phone ?? user.email ?? 'SecureChat account',
                  ),
                ),
              const Divider(),
              ListTile(
                leading: _isSyncingContacts
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.contacts, color: AppTheme.primaryColor),
                title: const Text('Connect contacts'),
                subtitle: const Text('Find friends already on SecureChat'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _isSyncingContacts ? null : _syncContacts,
              ),
              const Divider(),
              const _SettingsTile(
                icon: Icons.notifications,
                title: 'Notifications',
                subtitle: 'Manage notification preferences',
              ),
              const _SettingsTile(
                icon: Icons.lock,
                title: 'Privacy',
                subtitle: 'Last seen, profile photo, about',
              ),
              const _SettingsTile(
                icon: Icons.security,
                title: 'Security',
                subtitle: 'Security code and verification',
              ),
              const _SettingsTile(
                icon: Icons.storage,
                title: 'Storage',
                subtitle: 'Media and cache management',
              ),
              const _SettingsTile(
                icon: Icons.help_outline,
                title: 'Help',
                subtitle: 'FAQs and contact support',
              ),
              const Divider(),
              const _SettingsTile(
                icon: Icons.info_outline,
                title: 'About',
                subtitle: 'SecureChat v1.0.0',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {},
    );
  }
}
