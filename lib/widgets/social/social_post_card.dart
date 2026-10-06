import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../screens/social/private_image.dart';

class SocialPostCard extends StatefulWidget {
  const SocialPostCard({super.key, required this.post, required this.own,
    required this.preview, required this.onAction, required this.onComment,
    required this.onShare});
  final Publication post;
  final bool own, preview;
  final ValueChanged<String> onAction;
  final VoidCallback onComment, onShare;

  @override
  State<SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<SocialPostCard> {
  bool saved = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final image = p.assetImage == null ? null : AssetImage(p.assetImage!);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9EAF0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            CircleAvatar(
              radius: 19, backgroundColor: const Color(0xFFEBEDFC),
              backgroundImage: image,
              child: image == null ? Text(p.author.substring(0, 1).toUpperCase()) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.author, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF22242C))),
              const SizedBox(height: 2),
              Text(widget.preview ? 'Comunidade criativa • prévia' : 'Compartilhado com suas conexões', style: const TextStyle(fontSize: 11, color: Color(0xFF858794))),
            ])),
            PopupMenuButton<String>(
              tooltip: 'Opções da publicação',
              onSelected: widget.onAction,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'report', child: Text('Denunciar')),
                if (!widget.own) const PopupMenuItem(value: 'block', child: Text('Bloquear')),
                if (widget.own) ...[
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  const PopupMenuItem(value: 'delete', child: Text('Excluir')),
                ],
              ],
            ),
          ]),
        ),
        if (p.assetImage != null) GestureDetector(
          onDoubleTap: () { if (!p.liked) widget.onAction('like'); },
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.asset(p.assetImage!, fit: BoxFit.cover,
              semanticLabel: 'Postagem de ${p.author}',
              errorBuilder: (_, e, s) => const Center(child: Icon(Icons.broken_image_outlined, size: 40))),
          ),
        ) else if (p.media != null) PrivateImage(media: p.media!),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 0),
          child: Row(children: [
            IconButton(
              tooltip: p.liked ? 'Descurtir' : 'Curtir',
              onPressed: () => widget.onAction('like'),
              icon: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
                child: Icon(p.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(p.liked), color: p.liked ? const Color(0xFFE14E69) : const Color(0xFF30323A), size: 27),
              ),
            ),
            IconButton(tooltip: 'Comentar', onPressed: widget.onComment, icon: const Icon(Icons.chat_bubble_outline_rounded, size: 25, color: Color(0xFF30323A))),
            IconButton(tooltip: 'Compartilhar referência', onPressed: widget.onShare, icon: const Icon(Icons.send_outlined, size: 26, color: Color(0xFF30323A))),
            const Spacer(),
            IconButton(
              tooltip: saved ? 'Remover dos salvos desta sessão' : 'Salvar nesta sessão',
              onPressed: () => setState(() => saved = !saved),
              icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 27, color: const Color(0xFF30323A)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.likes} curtidas', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 7),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${p.author}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: p.text),
            ]), style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF353742))),
            const SizedBox(height: 5),
            InkWell(onTap: widget.onComment, child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Ver comentários', style: TextStyle(fontSize: 13, color: Color(0xFF858794))),
            )),
            Row(children: [
              const Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFF9A9CA8)),
              const SizedBox(width: 4),
              Text(widget.preview ? 'CONTEÚDO DE DEMONSTRAÇÃO' : 'VISIBILIDADE PROTEGIDA', style: const TextStyle(fontSize: 9, letterSpacing: 1, color: Color(0xFF9A9CA8))),
              if (saved) const Expanded(child: Text('Salvo nesta sessão', textAlign: TextAlign.end, style: TextStyle(fontSize: 10, color: Color(0xFF5658D9)))),
            ]),
          ]),
        ),
      ]),
    );
  }
}
