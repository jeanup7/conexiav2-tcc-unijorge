import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/design_system.dart';
import '../../theme/design_tokens.dart';

class PrivateImage extends StatefulWidget {
  const PrivateImage({
    super.key,
    required this.media,
    this.height = 240,
    this.endpoint,
    this.fit = BoxFit.cover,
  });
  final String media;
  final String? endpoint;
  final double height;
  final BoxFit fit;
  @override
  State<PrivateImage> createState() => _PrivateImageState();
}

class _PrivateImageState extends State<PrivateImage> {
  Future<Uint8List>? future;
  Future<Uint8List> load() async {
    final result = await AppScope.of(context).api
        .request('GET', widget.endpoint ?? '/media/${widget.media}');
    return base64Decode(result['data'] as String);
  }

  Widget fallback() => SizedBox(
    height: widget.height,
    child: const Center(
      child: Tooltip(
        message: 'Imagem indisponível',
        child: Icon(Icons.broken_image_outlined),
      ),
    ),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= load();
  }

  @override
  void didUpdateWidget(covariant PrivateImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media != widget.media ||
        oldWidget.endpoint != widget.endpoint) {
      future = load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return fallback();
      }
      if (snapshot.connectionState != ConnectionState.done ||
          !snapshot.hasData) {
        return MediaSkeleton(height: widget.height);
      }
      return Image.memory(
        snapshot.data!,
        height: widget.height,
        width: double.infinity,
        fit: widget.fit,
        semanticLabel: 'Imagem da publicação',
        frameBuilder: (context, child, frame, synchronous) => AnimatedOpacity(
          opacity: frame == null && !synchronous ? 0 : 1,
          duration: ConexiaMotion.duration(context),
          child: child,
        ),
        errorBuilder: (_, e, s) => fallback(),
      );
    },
  );
}
