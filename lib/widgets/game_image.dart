import 'package:flutter/material.dart';

import '../services/browser_image_store.dart';

class GameImage extends StatelessWidget {
  const GameImage({
    super.key,
    this.assetPath,
    this.browserImageId,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String? assetPath;
  final String? browserImageId;
  final IconData fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final id = browserImageId;
    if (id != null && id.isNotEmpty) {
      return FutureBuilder(
        future: BrowserImageStore.instance.read(id),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (snapshot.hasError ||
              (snapshot.connectionState == ConnectionState.done &&
                  bytes == null)) {
            return _fallback();
          }
          if (bytes == null) {
            return _fallback();
          }
          return Image.memory(
            bytes,
            fit: fit,
            errorBuilder: (context, error, stack) => _fallback(),
          );
        },
      );
    }
    final path = assetPath;
    if (path == null || path.trim().isEmpty) return _fallback();
    return Image.asset(
      path,
      fit: fit,
      errorBuilder: (context, error, stack) => _fallback(),
    );
  }

  Widget _fallback() => Container(
    color: const Color(0xFF1A2637),
    child: Center(
      child: Icon(fallback, size: 36, color: const Color(0xFF8290A3)),
    ),
  );
}
