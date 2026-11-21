import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'media_widgets.dart';

const maxMediaBytes = 50 * 1024 * 1024; // matches the 50 MB bucket limit

const _mimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'mkv': 'video/x-matroska',
};

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

  final _picker = ImagePicker();
  Timer? _ticker;
  bool _foreground = true;
  bool _marking = false;
  bool _uploading = false;

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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _attach() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    try {
      final XFile? file = kind == 'image'
          ? await _picker.pickImage(
              source: ImageSource.gallery, imageQuality: 85, maxWidth: 2048)
          : await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      await _sendMedia(file, kind);
    } catch (e) {
      _snack('Could not open your gallery: $e');
    }
  }

  String _extension(String name, String kind) {
    final dot = name.lastIndexOf('.');
    var e = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    e = e.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (e.isEmpty || e.length > 5) e = kind == 'image' ? 'jpg' : 'mp4';
    return e;
  }

  Future<void> _sendMedia(XFile file, String kind) async {
    final size = await file.length();
    if (size > maxMediaBytes) {
      _snack('That file is too big. The limit is 50 MB.');
      return;
    }
    if (!mounted) return;
    setState(() => _uploading = true);
    final ext = _extension(file.name, kind);
    final mime = _mimeByExt[ext] ?? (kind == 'image' ? 'image/jpeg' : 'video/mp4');
    final path = '${widget.chatId}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      await db.storage.from(mediaBucket).upload(
            path,
            File(file.path),
            fileOptions: FileOptions(contentType: mime),
          );
      // Anything typed in the box is sent as the caption.
      final caption = _controller.text.trim();
      await db.from('tc_messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _meId,
        'body': caption,
        'media_path': path,
        'media_type': kind,
      });
      _controller.clear();
    } catch (e) {
      _snack('Could not send the ${kind == 'image' ? 'photo' : 'video'}: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
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
                    final mediaPath = m['media_path'] as String?;
                    final body = m['body'] as String? ?? '';
                    return Align(
                      key: ValueKey(m['id']),
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
                            if (mediaPath != null)
                              Padding(
                                padding: EdgeInsets.only(
                                    bottom: body.isEmpty ? 0 : 6),
                                child: MediaThumb(
                                  path: mediaPath,
                                  type: (m['media_type'] as String?) ?? 'image',
                                ),
                              ),
                            if (body.isNotEmpty) Text(body),
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
          if (_uploading) const LinearProgressIndicator(minHeight: 3),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Send a photo or video',
                    onPressed: _uploading ? null : _attach,
                    icon: const Icon(Icons.attach_file),
                  ),
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
