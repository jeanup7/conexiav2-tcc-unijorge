import '../../widgets/design_system.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/social/profile_avatar.dart';

import 'package:flutter/material.dart';

import '../../state/preview_store.dart';
import '../../widgets/common.dart';
import '../../widgets/social/post_gallery.dart';
import 'feed_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    this.store,
    this.embedded = false,
  });
  final String userId;
  final PreviewStore? store;
  final bool embedded;
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Future<Map<String, dynamic>>? profile;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.store == null) {
      profile ??= AppScope.of(context).api
          .request('GET', '/profiles/${Uri.encodeComponent(widget.userId)}');
    }
  }

  @override
  void didUpdateWidget(covariant UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.store != widget.store) {
      profile = widget.store == null
          ? AppScope.of(context).api.request(
              'GET',
              '/profiles/${Uri.encodeComponent(widget.userId)}',
            )
          : null;
    }
  }

  Widget content(String name, String bio, bool private, {String? media}) {
    final local = widget.store?.forUser(widget.userId) ?? [];
    final photo = widget.store?.profiles
        .where((p) => p.id == widget.userId)
        .firstOrNull
        ?.photo;
    final ImageProvider? avatar = photo?.asset != null
        ? AssetImage(photo!.asset!)
        : photo?.bytes != null
        ? MemoryImage(photo!.bytes!)
        : null;
    return ContentFrame(
      child: HeaderBody(
        header: SurfaceCard(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          padding: const EdgeInsets.all(24),
          gradient: ConexiaColors.hero,
          child: Column(
            children: [
              ProfileAvatar(
                media: media,
                image: avatar,
                radius: 42,
                label: 'Foto de $name',
              ),
              const SizedBox(height: 12),
              Text(name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              StatusPill(
                label: private ? 'Perfil privado' : 'Perfil público',
                positive: true,
              ),
              if (bio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(bio, textAlign: TextAlign.center),
                ),
              if (widget.store != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${local.length} publicações • perfil de demonstração',
                  ),
                ),
            ],
          ),
        ),
        body: widget.store == null
            ? FeedScreen(key: ValueKey(widget.userId), authorId: widget.userId)
            : local.isEmpty
            ? const EmptyState(
                message:
                    'Ainda não há publicações. Use a aba Criar para começar.',
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: local.length,
                itemBuilder: (_, i) {
                  final post = local[i];
                  return InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(name)),
                          body: ContentFrame(
                            child: FeedScreen(
                              preview: true,
                              previewStore: widget.store,
                              authorId: widget.userId,
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: post.photos.isEmpty
                              ? Container(
                                  color: const Color(0xFFEBEDFC),
                                  padding: const EdgeInsets.all(8),
                                  child: Center(
                                    child: Text(
                                      post.text,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                              : PostPhotoView(photo: post.photos.first),
                        ),
                        if (post.photos.length > 1)
                          const Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(
                              Icons.collections,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final Widget body;
    if (store != null) {
      body = AnimatedBuilder(
        animation: store,
        builder: (_, _) {
          final user = store.profiles
              .where((p) => p.id == widget.userId)
              .firstOrNull;
          return content(
            user?.name ?? 'Perfil indisponível',
            'Um espaço para compartilhar criatividade e boas ideias.',
            true,
          );
        },
      );
    } else {
      body = FutureBuilder<Map<String, dynamic>>(
        future: profile,
        builder: (_, s) {
          if (s.hasError) {
            return Center(child: EmptyState(message: s.error.toString()));
          }
          if (s.connectionState != ConnectionState.done || !s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return content(
            s.data!['name'] as String,
            s.data!['bio'] as String,
            s.data!['private'] == 1,
            media: s.data!['avatar'] as String?,
          );
        },
      );
    }
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Perfil')),
            body: body,
          );
  }
}
