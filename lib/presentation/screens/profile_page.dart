import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/auth/auth_event.dart';
import '../blocs/auth/auth_state.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

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

  void _editName() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    _nameController.text = user.displayName ?? '';

    final name = await _promptText(
      title: 'Edit Display Name',
      controller: _nameController,
      hint: 'Your name',
    );
    if (name == null || !mounted) return;

    context
        .read<AuthBloc>()
        .add(AuthProfileUpdateRequested(displayName: name.trim()));
  }

  void _editUsername() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    _usernameController.text = user.username ?? '';

    final username = await _promptText(
      title: 'Edit Username',
      controller: _usernameController,
      hint: 'username',
    );
    if (username == null || !mounted) return;

    context
        .read<AuthBloc>()
        .add(AuthProfileUpdateRequested(username: username.trim()));
  }

  Future<String?> _promptText({
    required String title,
    required TextEditingController controller,
    required String hint,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
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
        listener: (context, state) {
          if (state.status == AuthStatus.error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'An error occurred'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
        },
        builder: (context, state) {
          final user = state.user;
          final isSaving = state.status == AuthStatus.loading;

          if (user == null) {
            return const Center(child: Text('Not signed in'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 16),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: AppTheme.primaryColor,
                      child: user.avatarUrl != null
                          ? ClipOval(
                              child: Image.network(
                                user.avatarUrl!,
                                width: 112,
                                height: 112,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 56,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 56,
                              color: Colors.white,
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: IconButton(
                        onPressed: isSaving ? null : _pickAvatar,
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.photo_camera, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _ProfileTile(
                icon: Icons.person,
                label: 'Display Name',
                value: user.displayName ?? 'Set your name',
                onTap: isSaving ? null : _editName,
              ),
              _ProfileTile(
                icon: Icons.alternate_email,
                label: 'Username',
                value: user.username ?? 'Set a username',
                onTap: isSaving ? null : _editUsername,
              ),
              if (user.phone != null)
                _ProfileTile(
                  icon: Icons.phone,
                  label: 'Phone',
                  value: user.phone!,
                  onTap: null,
                ),
              if (user.email != null)
                _ProfileTile(
                  icon: Icons.email,
                  label: 'Email',
                  value: user.email!,
                  onTap: null,
                ),
              const SizedBox(height: 24),
              if (isSaving) const Center(child: CircularProgressIndicator()),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        trailing: onTap != null ? const Icon(Icons.edit) : null,
        onTap: onTap,
      ),
    );
  }
}
