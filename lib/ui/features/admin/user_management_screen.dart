import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/csv_export.dart';
import '../../core/widgets.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  late Future<List<Map<String, dynamic>>> _users;

  @override
  void initState() {
    super.initState();
    _users = ref.read(stationRepositoryProvider).loadAdminUsers();
  }

  void _reload() {
    setState(() {
      _users = ref.read(stationRepositoryProvider).loadAdminUsers();
    });
  }

  Future<void> _changeRole(Map<String, dynamic> user, String role) async {
    final email = user['email'] as String? ?? 'this account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(
              role == 'admin'
                  ? 'Grant administrator access?'
                  : 'Remove administrator access?',
            ),
            content: Text(
              role == 'admin'
                  ? 'This will allow $email to manage stations, users, tickets and reports.'
                  : 'This will change $email back to a normal user account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(role == 'admin' ? 'Grant admin' : 'Change role'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(stationRepositoryProvider)
          .setUserRole(userId: user['id'] as String, role: role);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User role updated.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  Future<void> _copyCsv(List<Map<String, dynamic>> users) async {
    final lines = <String>['email,display_name,role,created_at'];
    for (final user in users) {
      lines.add(
        [
          csvCell(user['email']),
          csvCell(user['display_name']),
          csvCell(user['role']),
          csvCell(user['created_at']),
        ].join(','),
      );
    }
    final saved = await saveCsvFile(
      fileName: 'chargemy_users_${DateTime.now().millisecondsSinceEpoch}.csv',
      content: lines.join('\n'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'User CSV saved successfully.' : 'CSV export cancelled.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Users and roles'),
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(friendlyErrorMessage(snapshot.error)));
        }
        final users = snapshot.data ?? const <Map<String, dynamic>>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: Text('${users.length} registered account(s)'),
                subtitle: const Text('Only administrators can change roles.'),
                trailing: IconButton(
                  tooltip: 'Export users',
                  onPressed: () => _copyCsv(users),
                  icon: const Icon(Icons.download_outlined),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final user in users)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      ((user['display_name'] as String?)?.isNotEmpty == true
                              ? user['display_name'] as String
                              : user['email'] as String? ?? '?')[0]
                          .toUpperCase(),
                    ),
                  ),
                  title: Text(
                    (user['display_name'] as String?)?.isNotEmpty == true
                        ? user['display_name'] as String
                        : 'Unnamed user',
                  ),
                  subtitle: Text(user['email'] as String? ?? 'No email'),
                  trailing: _RoleSelector(
                    role: user['role'] as String? ?? 'user',
                    onSelected: (role) {
                      if (role != user['role']) _changeRole(user, role);
                    },
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.role, required this.onSelected});

  final String role;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    final color =
        isAdmin
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return PopupMenuButton<String>(
      tooltip: 'Change user role',
      onSelected: onSelected,
      itemBuilder:
          (_) => const [
            PopupMenuItem(value: 'user', child: Text('User')),
            PopupMenuItem(value: 'admin', child: Text('Administrator')),
          ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.person_outline,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                isAdmin ? 'Admin' : 'User',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down, color: color, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}
