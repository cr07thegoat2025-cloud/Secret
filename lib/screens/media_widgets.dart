import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';

const mediaBucket = 'tc-media';

/// A photo or video inside a chat bubble. Files are private, so each one is
/// shown through a temporary signed link (valid for one hour).
class MediaThumb extends StatefulWidget {
  final String path;
  final String type; // 'image' or 'video'

  const MediaThumb({super.key, required this.path, required this.type});

  @override
  State<MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<MediaThumb> {
  late final Future<String> _url =
      db.storage.from(mediaBucket).createSignedUrl(widget.path, 3600);

  Widget _box(BuildContext context, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 220,
        height: 220,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) {
          return _box(
              context,
              const Center(
                  child: Icon(Icons.broken_image_outlined, size: 40)));
        }
        if (!snap.hasData) {
          return _box(context,
              const Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final url = snap.data!;
        if (widget.type == 'image') {
          return GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ImagePage(url: url))),
            child: _box(
              context,
              Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 40)),
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => VideoPage(url: url))),
          child: _box(
            context,
            Container(
              color: Colors.black87,
              child: const Center(
                child: Icon(Icons.play_circle_fill,
                    size: 56, color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ImagePage extends StatelessWidget {
  final String url;
  const ImagePage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Could not load photo',
                style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class VideoPage extends StatefulWidget {
  final String url;
  const VideoPage({super.key, required this.url});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: _failed
            ? const Text('Could not play this video',
                style: TextStyle(color: Colors.white))
            : !_c.value.isInitialized
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
                    child: AspectRatio(
                      aspectRatio: _c.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(_c),
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _c,
                            builder: (context, v, _) => v.isPlaying
                                ? const SizedBox.shrink()
                                : const Positioned.fill(
                                    child: Center(
                                      child: Icon(Icons.play_circle_fill,
                                          size: 72, color: Colors.white70),
                                    ),
                                  ),
                          ),
                          VideoProgressIndicator(_c, allowScrubbing: true),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
