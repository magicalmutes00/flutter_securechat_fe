import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/models/group_model.dart';
import '../../data/services/api_client.dart';
import '../blocs/chat/chat_bloc.dart';
import '../blocs/chat/chat_event.dart';
import '../blocs/chat/chat_state.dart';
import '../widgets/ui/ui.dart';
import 'group_chat_screen.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final Set<String> _selectedIds = {};
  final ApiClient _apiClient = ApiClient();
  bool _isCreating = false;

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<ChatBloc>().add(ChatSearchUsers(query));
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty || _selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a group name and select members')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final data = await _apiClient.createGroup(
        name: name,
        memberIds: _selectedIds.toList(),
      );
      final group = Group.fromJson(data);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(group: group),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          _isCreating
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _createGroup,
                  child: const Text('Create'),
                ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                hintText: 'Group name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users to add...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_selectedIds.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w600),
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
                          ? 'Search for users to add'
                          : 'No users found',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: state.searchResults.length,
                  itemBuilder: (context, index) {
                    final user = state.searchResults[index];
                    final isSelected = _selectedIds.contains(user.id);
                    return CheckboxListTile(
                      value: isSelected,
                      secondary: AppAvatar(
                        label: user.displayName ??
                            user.email ??
                            user.phone ??
                            'U',
                        radius: 20,
                      ),
                      title: Text(user.displayName ?? 'No name'),
                      subtitle: Text(user.email ?? user.phone ?? ''),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIds.add(user.id);
                          } else {
                            _selectedIds.remove(user.id);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
