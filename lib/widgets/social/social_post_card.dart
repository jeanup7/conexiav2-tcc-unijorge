import '../design_system.dart';
import '../../theme/design_tokens.dart';
import '../../models/content_categories.dart';
import 'profile_avatar.dart';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import 'post_gallery.dart';

class SocialPostCard extends StatefulWidget {
  const SocialPostCard({
    super.key,
    required this.post,
    required this.own,
    required this.preview,
    required this.onAction,
    required this.onComment,
    required this.onShare,
    this.onProfile,
    this.onDiscuss,
  });
  final Publication post;
  final bool own, preview;
  final ValueChanged<String> onAction;
  final VoidCallback onComment, onShare;
  final VoidCallback? onProfile, onDiscuss;

  @override
  State<SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<SocialPostCard> {
  bool saved = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final photo = p.photos.firstOrNull;
    final ImageProvider? image = photo?.asset != null
        ? AssetImage(photo!.asset!)
        : photo?.bytes != null
        ? MemoryImage(photo!.bytes!)
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ConexiaColors.line),
        boxShadow: ConexiaColors.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
            child: Row(
              children: [
                InkWell(
                  key: ValueKey('profile-${p.userId}'),
                  onTap: widget.onProfile,
                  borderRadius: BorderRadius.circular(24),
                  child: Semantics(
                    button: true,
                    label: 'Abrir perfil de ${p.author}',
                    child: ProfileAvatar(
                      media: p.authorAvatar,
                      image: image,
                      radius: 22,
                      label: 'Foto de ${p.author}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: widget.onProfile,
                        child: Text(
                          p.author,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF22242C),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.preview
                            ? 'Comunidade criativa • prévia'
                            : contentCategories[p.category] ?? 'Outros',
                        style: const TextStyle(
                          fontSize: 12,
                          color: ConexiaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.ellipsisVertical, size: 21),
                  tooltip: 'Opções da publicação',
                  onSelected: widget.onAction,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Denunciar'),
                    ),
                    if (!widget.own)
                      const PopupMenuItem(
                        value: 'block',
                        child: Text('Bloquear'),
                      ),
                    if (widget.own) ...[
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Excluir'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (p.photos.isNotEmpty)
            PostGallery(
              photos: p.photos,
              onDoubleTap: () {
                if (!p.liked) widget.onAction('like');
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 0),
            child: Row(
              children: [
                PressFeedback(
                  child: IconButton(
                    tooltip: p.liked ? 'Descurtir' : 'Curtir',
                    onPressed: () => widget.onAction('like'),
                    icon: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child:
                          Icon(
                                p.liked
                                    ? Icons.favorite_rounded
                                    : LucideIcons.heart,
                                key: ValueKey(p.liked),
                                color: p.liked
                                    ? const Color(0xFFE14E69)
                                    : ConexiaColors.ink,
                                size: 27,
                              )
                              .animate(
                                target: p.liked ? 1 : 0,
                                autoPlay: !MediaQuery.disableAnimationsOf(
                                  context,
                                ),
                              )
                              .scaleXY(
                                begin: MediaQuery.disableAnimationsOf(context)
                                    ? 1
                                    : .92,
                                end: 1,
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                              ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Comentar',
                  onPressed: widget.onComment,
                  icon: const Icon(
                    LucideIcons.messageCircle,
                    size: 25,
                    color: ConexiaColors.ink,
                  ),
                ),
                IconButton(
                  tooltip: 'Compartilhar referência',
                  onPressed: widget.onShare,
                  icon: const Icon(
                    LucideIcons.send,
                    size: 26,
                    color: ConexiaColors.ink,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: saved
                      ? 'Remover dos salvos desta sessão'
                      : 'Salvar nesta sessão',
                  onPressed: () => setState(() => saved = !saved),
                  icon: Icon(
                    saved ? Icons.bookmark_rounded : LucideIcons.bookmark,
                    size: 27,
                    color: ConexiaColors.ink,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.likes} curtidas',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: ConexiaColors.ink,
                  ),
                ),
                const SizedBox(height: 9),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${p.author}  ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: p.text),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF353742),
                  ),
                ),
                const SizedBox(height: 5),
                InkWell(
                  onTap: widget.onComment,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Ver comentários',
                      style: TextStyle(
                        fontSize: 13,
                        color: ConexiaColors.muted,
                      ),
                    ),
                  ),
                ),
                if (widget.onDiscuss != null)
                  TextButton.icon(
                    onPressed: widget.onDiscuss,
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: const Text('Vamos conversar?'),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 12,
                      color: ConexiaColors.muted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        widget.preview
                            ? 'CONTEÚDO DE DEMONSTRAÇÃO'
                            : 'VISIBILIDADE PROTEGIDA',
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: .7,
                          color: ConexiaColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (saved)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Salvo nesta sessão',
                      style: TextStyle(
                        fontSize: 11,
                        color: ConexiaColors.brand,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
