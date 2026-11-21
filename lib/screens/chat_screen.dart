import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';

/// "just now", "5 min ago", "3 h ago", "2 d ago". Older than a week: a date.
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 10) return 'just now'; // also covers small clock skew
  if (d.inSeconds < 60) return '${d.inSeconds} sec ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat.yMMMd().format(t);
}

DateTime? _parse(dynamic v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherName;

  const ChatScreen({super.key, required this.chatId, required this.otherName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _meId = db.auth.currentUser!.id;
  late final Stream<List<Map<String, dynamic>>> _stream = db
      .from('tc_messages')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('created_at', ascending: false)
      .limit(200);

  Timer? _ticker;
  bool _foreground = true;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-draw every 15 s so "5 min ago" keeps counting up.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _markRead();
  }

  /// Tell the server that the messages you can see on screen have been seen.
  Future<void> _markRead() async {
    if (_marking || !_foreground || !mounted) return;
    _marking = true;
    try {
      await db.rpc('tc_mark_read', params: {'p_chat': widget.chatId});
    } catch (_) {
      // Best effort. It will be retried on the next message or app resume.
    } finally {
      _marking = false;
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    try {
      await db.from('tc_messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _meId,
        'body': text,
      });
    } catch (e) {
      if (!mounted) return;
      _controller.text = text;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Message not sent: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherName)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final msgs = snap.data!;
                if (msgs.isEmpty) {
                  return const Center(child: Text('Say hi 👋'));
                }

                // Any message from them that I haven't marked as seen yet?
                final hasUnseen = msgs
                    .any((m) => m['sender_id'] != _meId && m['read_at'] == null);
                if (hasUnseen) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _markRead());
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final mine = m['sender_id'] == _meId;
                    final sent = _parse(m['created_at']);
                    final seen = _parse(m['read_at']);
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(m['body'] as String? ?? ''),
                            const SizedBox(height: 2),
                            if (sent != null)
                              Text(
                                  mine
                                      ? 'Sent ${timeAgo(sent)}'
                                      : timeAgo(sent),
                                  style: small),
                            if (mine)
                              Text(
                                seen != null
                                    ? 'Seen ${timeAgo(seen)}'
                                    : 'Not seen yet',
                                style: small?.copyWith(
                                  color: seen != null ? scheme.primary : null,
                                  fontWeight: seen != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
