import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/common.dart';

class PrivateImage extends StatefulWidget {
  const PrivateImage({super.key, required this.media, this.height = 240});
  final String media;
  final double height;
  @override
  State<PrivateImage> createState() => _PrivateImageState();
}
class _PrivateImageState extends State<PrivateImage> {
  Future<Map<String, dynamic>>? future;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); future ??= AppScope.of(context).api.request('GET', '/media/${widget.media}'); }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: future, builder: (context,snapshot) {
    if (snapshot.hasError) return const EmptyState(message: 'Imagem indisponível', icon: Icons.broken_image_outlined);
    if (!snapshot.hasData) return SizedBox(height: widget.height, child: const Center(child: CircularProgressIndicator()));
    return Image.memory(base64Decode(snapshot.data!['data'] as String), height: widget.height, width: double.infinity, fit: BoxFit.cover, semanticLabel: 'Imagem da publicação', errorBuilder: (_, e, s) => const EmptyState(message: 'Não foi possível exibir a imagem'));
  });
}
