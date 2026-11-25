import '../../models/models.dart';
import 'composer_screen.dart';
import '../../widgets/social/profile_heading.dart';
import '../../widgets/design_system.dart';
import '../../theme/design_tokens.dart';

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
  int? count;
  bool hasMore = false;
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
      count = null;
      hasMore = false;
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
          margin: EdgeInsets.fromLTRB(16, 16, 16, 24),
          padding: EdgeInsets.all(24),
          gradient: ConexiaPalette.of(context).hero,
          child: ProfileHeading(
            name: name,
            bio: bio,
            private: private,
            media: media,
            image: avatar,
            count: widget.store != null ? local.length : count,
            hasMore: hasMore,
          ),
        ),
        body: widget.store == null
            ? FeedScreen(
                key: ValueKey(widget.userId),
                authorId: widget.userId,
                onSummary: (value, more) {
                  if (mounted) {
                    setState(() {
                      count = value;
                      hasMore = more;
                    });
                  }
                },
              )
            : local.isEmpty
            ? SingleChildScrollView(
                child: widget.userId == 'preview-self'
                    ? FirstPublication(
                        onCreate: () async {
                          final post = await Navigator.push<Publication>(
                            context,
                            MaterialPageRoute<Publication>(
                              builder: (_) =>
                                  const ComposerScreen(preview: true),
                            ),
                          );
                          if (mounted && post != null) widget.store!.add(post);
                        },
                      )
                    : const EmptyState(message: 'Ainda não há publicações.'),
              )
            : GridView.builder(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.4,
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
                                  color: ConexiaPalette.of(context).tinted,
                                  padding: EdgeInsets.all(8),
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
                          Positioned(
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
            return Center(child: CircularProgressIndicator());
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
            appBar: AppBar(title: Text('Perfil')),
            body: body,
          );
  }
}
