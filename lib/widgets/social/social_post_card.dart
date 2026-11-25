import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../models/content_categories.dart';
import '../../theme/design_tokens.dart';
import 'post_gallery.dart';
import 'profile_avatar.dart';

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
    final variant = p.id.codeUnits.fold<int>(0, (a, b) => a + b) % 3;
    final textOnly = p.photos.isEmpty;
    return Container(
      margin: EdgeInsets.fromLTRB(
        variant == 1 ? 12 : 0,
        0,
        variant == 2 ? 12 : 0,
        28,
      ),
      decoration: BoxDecoration(
        color: textOnly
            ? ConexiaPalette.of(context).tinted
            : ConexiaPalette.of(context).surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(36),
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(8),
        ),
        border: Border.all(color: ConexiaPalette.of(context).line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 8, 12),
            child: Row(
              children: [
                InkWell(
                  key: ValueKey('profile-${p.userId}'),
                  onTap: widget.onProfile,
                  child: Semantics(
                    button: true,
                    label: 'Abrir perfil de ${p.author}',
                    child: ProfileAvatar(
                      media: p.authorAvatar,
                      image: p.photos.firstOrNull?.asset != null
                          ? AssetImage(p.photos.first.asset!)
                          : null,
                      radius: 20,
                      label: 'Foto de ${p.author}',
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (contentCategories[p.category] ?? 'Ideias')
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: ConexiaPalette.of(context).primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onProfile,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(
                          p.author,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ConexiaPalette.of(context).text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opções da publicação',
                  icon: Icon(Icons.more_horiz),
                  onSelected: widget.onAction,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'report', child: Text('Denunciar')),
                    if (!widget.own)
                      PopupMenuItem(value: 'block', child: Text('Bloquear')),
                    if (widget.own) ...[
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 24, 20),
            child: Text(
              p.text,
              style: TextStyle(
                fontSize: textOnly ? 24 : 18,
                fontWeight: textOnly ? FontWeight.w800 : FontWeight.w600,
                height: 1.4,
                letterSpacing: -.4,
                color: ConexiaPalette.of(context).text,
              ),
            ),
          ),
          if (!textOnly)
            Padding(
              padding: EdgeInsets.only(left: 12, right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                child: PostGallery(
                  photos: p.photos,
                  aspectRatio: variant == 0 ? 1.65 : 1.25,
                  onDoubleTap: () {
                    if (!p.liked) widget.onAction('like');
                  },
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _action(
                  p.liked ? 'Retirar impulso' : 'Dar impulso',
                  Icons.bolt,
                  () => widget.onAction('like'),
                  label: '${p.likes}',
                  active: p.liked,
                ),
                _action('Comentar', Icons.segment, widget.onComment),
                _action(
                  'Compartilhar referência',
                  Icons.north_east,
                  widget.onShare,
                ),
                _action(
                  saved
                      ? 'Remover dos salvos desta sessão'
                      : 'Salvar nesta sessão',
                  saved ? Icons.layers : Icons.layers_outlined,
                  () => setState(() => saved = !saved),
                  active: saved,
                ),
              ],
            ),
          ),
          if (widget.onDiscuss != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onDiscuss,
                icon: Icon(Icons.join_inner),
                label: Text('Vamos conversar?'),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Text(
              widget.preview
                  ? 'PRÉVIA LOCAL · CONTEÚDO DE DEMONSTRAÇÃO'
                  : saved
                  ? 'SALVO NESTA SESSÃO · VISIBILIDADE PROTEGIDA'
                  : 'VISIBILIDADE PROTEGIDA',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                color: ConexiaPalette.of(context).muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    String tooltip,
    IconData icon,
    VoidCallback action, {
    String? label,
    bool active = false,
  }) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: AnimatedContainer(
        duration: ConexiaMotion.duration(context),
        decoration: BoxDecoration(
          color: active
              ? ConexiaPalette.of(context).tinted
              : ConexiaPalette.of(context).surface,
          border: Border.all(color: ConexiaPalette.of(context).line),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
            minimumSize: Size(48, 48),
            foregroundColor: ConexiaPalette.of(context).text,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24),
              if (label != null) ...[SizedBox(width: 6), Text(label)],
            ],
          ),
        ),
      ),
    ),
  );
}
