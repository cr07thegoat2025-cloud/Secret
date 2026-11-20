import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import 'chat_screen.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  Future<void> _newChat(BuildContext context) async {
    final me = db.auth.currentUser!;
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: "Friend's email"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Start')),
        ],
      ),
    );
    if (email == null || email.trim().isEmpty || !context.mounted) return;

    try {
      final found = await db.rpc('tc_find_user', params: {'p_email': email});
      if (!context.mounted) return;
      final rows = List<Map<String, dynamic>>.from(found as List);
      if (rows.isEmpty) {
        _snack(context, 'No user found with that email.');
        return;
      }
      final other = rows.first;
      if (other['id'] == me.id) {
        _snack(context, "That's your own email.");
        return;
      }
      final chatId =
          await db.rpc('tc_start_chat', params: {'p_other': other['id']});
      if (!context.mounted) return;
      final name = (other['name'] as String?)?.isNotEmpty == true
          ? other['name'] as String
          : other['email'] as String;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ChatScreen(chatId: chatId as String, otherName: name)),
      );
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not start chat: $e');
    }
  }

  void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final me = db.auth.currentUser!;
    // Row Level Security means this only ever returns chats you belong to.
    final stream = db
        .from('tc_chats')
        .stream(primaryKey: ['id']).order('last_time', ascending: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TextChat'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => db.auth.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(context),
        child: const Icon(Icons.chat),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Hide chats nobody has written in yet.
          final chats =
              snap.data!.where((c) => c['last_message'] != null).toList();
          if (chats.isEmpty) {
            return const Center(
                child: Text('No chats yet.\nTap the button to start one.',
                    textAlign: TextAlign.center));
          }
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = chats[i];
              final otherId = c['user_a'] == me.id ? c['user_b'] : c['user_a'];
              return _ChatTile(
                key: ValueKey(c['id']),
                chatId: c['id'] as String,
                otherId: otherId as String,
                lastMessage: c['last_message'] as String? ?? '',
                lastTime: c['last_time'] == null
                    ? null
                    : DateTime.parse(c['last_time'] as String).toLocal(),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatefulWidget {
  final String chatId;
  final String otherId;
  final String lastMessage;
  final DateTime? lastTime;

  const _ChatTile({
    super.key,
    required this.chatId,
    required this.otherId,
    required this.lastMessage,
    required this.lastTime,
  });

  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  String _name = '…';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    try {
      final row = await db
          .from('tc_profiles')
          .select('name,email')
          .eq('id', widget.otherId)
          .maybeSingle();
      if (!mounted) return;
      final name = (row?['name'] as String?) ?? '';
      setState(() => _name =
          name.isNotEmpty ? name : (row?['email'] as String? ?? 'Unknown'));
    } catch (_) {
      if (mounted) setState(() => _name = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
          child: Text(_name.isEmpty ? '?' : _name[0].toUpperCase())),
      title: Text(_name),
      subtitle: Text(widget.lastMessage,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: widget.lastTime == null
          ? null
          : Text(DateFormat.jm().format(widget.lastTime!),
              style: Theme.of(context).textTheme.bodySmall),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ChatScreen(chatId: widget.chatId, otherName: _name)),
      ),
    );
  }
}
