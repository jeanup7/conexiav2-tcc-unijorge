import '../../widgets/design_system.dart';
import '../../theme/design_tokens.dart';
import '../family_activity_screen.dart';
import '../../widgets/social/post_exposure.dart';
import '../../state/preview_store.dart';
import 'user_profile_screen.dart';
import '../../models/preview_content.dart';
import '../../widgets/social/story_avatar.dart';
import '../../widgets/social/social_post_card.dart';
import '../../widgets/social/feed_skeleton.dart';
import '../../repositories/social_repository.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../widgets/common.dart';
import '../denuncia_screen.dart';
import 'composer_screen.dart';
import '../../widgets/social/post_gallery.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    this.ownOnly = false,
    this.preview = false,
    this.previewStore,
    this.authorId,
  });
  final bool ownOnly;
  final bool preview;
  final PreviewStore? previewStore;
  final String? authorId;
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Publication> posts = [], stories = [];
  final scroll = ScrollController();
  bool busy = true, more = false;
  bool initialized = false;
  bool initializedPreview = false;
  SocialRepository? repository;
  String? storyError;
  void refreshSocial() {
    if (mounted && !widget.preview) load();
  }

  void syncPost() {
    final changed = repository?.postChange.value;
    if (!mounted || changed == null) return;
    setState(
      () => posts = posts
          .map(
            (p) => p.id == changed.id
                ? p.copyWith(likes: changed.likes, liked: changed.liked)
                : p,
          )
          .toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.previewStore?.addListener(_syncPreview);
  }

  void _syncPreview() {
    if (mounted) {
      final updated = widget.previewStore!.posts;
      final inserted =
          updated.isNotEmpty && !posts.any((p) => p.id == updated.first.id);
      setState(() {
        posts = updated;
        stories = widget.previewStore!.stories;
      });
      if (inserted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) scroll.jumpTo(0);
        });
      }
    }
  }

  @override
  void dispose() {
    repository?.revision.removeListener(refreshSocial);
    repository?.postChange.removeListener(syncPost);
    widget.previewStore?.removeListener(_syncPreview);
    scroll.dispose();
    super.dispose();
  }

  String? cursor;
  int requestGeneration = 0;
  final pendingActions = <String>{};
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      if (!widget.preview) {
        repository = AppScope.of(context).social;
        repository!.revision.addListener(refreshSocial);
        repository!.postChange.addListener(syncPost);
      }
      load();
    }
  }

  Future<void> load({bool append = false}) async {
    if (append && (more || busy || cursor == null)) return;
    final generation = ++requestGeneration;
    if (widget.preview) {
      if (widget.previewStore != null) {
        posts = widget.previewStore!.posts;
        stories = widget.previewStore!.stories;
      } else if (!initializedPreview) {
        initializedPreview = true;
        posts = List.of(previewPublications);
        stories = previewPublications
            .map(
              (p) => Publication(
                id: 'story-${p.id}',
                userId: p.userId,
                author: p.author,
                text: p.text,
                likes: 0,
                liked: false,
                assetImage: p.assetImage,
                expires:
                    DateTime.now()
                        .add(const Duration(hours: 24))
                        .millisecondsSinceEpoch /
                    1000,
              ),
            )
            .toList();
      }
      setState(() {
        busy = false;
        error = null;
        cursor = null;
      });
      return;
    }
    setState(() {
      if (append) {
        more = true;
      } else {
        busy = true;
      }
      error = null;
    });
    try {
      final state = AppScope.of(context);
      final version = state.api.sessionVersion;
      final result = await state.social.feed(
        cursor: append ? cursor : null,
        authorId:
            widget.authorId ?? (widget.ownOnly ? state.account!.id : null),
      );
      if (!mounted || generation != requestGeneration) return;
      state.api.checkSession(version);
      List<Publication>? loadedStories;
      if (!append && !widget.ownOnly && widget.authorId == null) {
        try {
          loadedStories = (await state.social.feed(stories: true)).items;
          storyError = null;
        } catch (_) {
          state.api.checkSession(version);
          loadedStories = [];
          storyError = 'Não foi possível atualizar os stories.';
        }
      }
      if (mounted && generation == requestGeneration) {
        setState(() {
          posts = append
              ? {
                  for (final p in [...posts, ...result.items]) p.id: p,
                }.values.toList()
              : result.items;
          cursor = result.cursor;
          if (loadedStories != null) stories = loadedStories;
        });
      }
    } catch (e) {
      if (mounted && generation == requestGeneration) {
        if (append) {
          showFeedback(context, e);
        } else {
          setState(() => error = e.toString());
        }
      }
    } finally {
      if (mounted && generation == requestGeneration) {
        setState(() {
          busy = false;
          more = false;
        });
      }
    }
  }

  Future<void> create(bool story) async {
    if (widget.preview) {
      final post = await Navigator.push<Publication>(
        context,
        MaterialPageRoute(
          builder: (_) => ComposerScreen(preview: true, story: story),
        ),
      );
      if (post != null && mounted) {
        if (widget.previewStore != null) {
          widget.previewStore!.add(post, story: story);
        } else {
          setState(() {
            if (story) {
              stories = [post, ...stories];
            } else {
              posts = [post, ...posts];
            }
          });
        }
      }
      return;
    }
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComposerScreen(story: story)),
    );
    if (result == true && mounted && repository == null) load();
  }

  Future<void> action(Publication post, String value) async {
    if (widget.preview) {
      if (widget.previewStore != null) {
        if (value == 'like') {
          widget.previewStore!.like(post.id);
        } else if (value == 'delete') {
          widget.previewStore!.delete(post.id);
        } else if (value == 'block') {
          widget.previewStore!.block(post.userId);
        } else {
          showFeedback(
            context,
            'Demonstração: esta ação exige uma conta verificada.',
          );
        }
        return;
      }
      if (value == 'like') {
        setState(
          () => posts = posts
              .map(
                (p) => p.id != post.id
                    ? p
                    : p.copyWith(
                        likes: p.likes + (p.liked ? -1 : 1),
                        liked: !p.liked,
                      ),
              )
              .toList(),
        );
      } else if (value == 'delete' || value == 'block') {
        setState(
          () => posts.removeWhere(
            (p) =>
                value == 'delete' ? p.id == post.id : p.userId == post.userId,
          ),
        );
        showFeedback(
          context,
          'Simulação local aplicada. Nenhum dado foi alterado no servidor.',
        );
      } else {
        showFeedback(
          context,
          'Prévia local: esta ação exige uma conta verificada no aplicativo real.',
        );
      }
      return;
    }
    if (value == 'report') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DenunciaScreen(target: post.id),
        ),
      );
      return;
    }
    if (value == 'edit') {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ComposerScreen(postId: post.id, initialText: post.text),
        ),
      );
      if (result == true && mounted && repository == null) load();
      return;
    }
    if (!pendingActions.add(post.id)) return;
    try {
      if (value == 'delete' || value == 'block') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              value == 'delete'
                  ? 'Excluir publicação?'
                  : 'Bloquear este perfil?',
            ),
            content: Text(
              value == 'delete'
                  ? 'Esta ação remove a publicação e seus comentários.'
                  : 'O bloqueio impede visibilidade e novas interações entre os perfis.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        );
        if (confirm != true || !mounted) return;
      }
      final api = AppScope.of(context).api;
      if (value == 'like') {
        final result = await api.request('POST', '/posts/${post.id}/like', {
          'liked':
              !(posts.where((p) => p.id == post.id).firstOrNull ?? post).liked,
        });
        if (mounted) {
          repository?.postChange.value = post.copyWith(
            likes: result['likes'] as int,
            liked: result['liked'] as bool,
          );
          setState(
            () => posts = posts
                .map(
                  (p) => p.id == post.id
                      ? p.copyWith(
                          likes: result['likes'] as int,
                          liked: result['liked'] as bool,
                        )
                      : p,
                )
                .toList(),
          );
        }
        return;
      }
      if (value == 'delete') await api.request('DELETE', '/posts/${post.id}');
      if (value == 'block') {
        await api.request('POST', '/blocks', {'target': post.userId});
      }
      if (mounted) repository?.invalidate();
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      pendingActions.remove(post.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).account;
    if (user == null && !widget.preview) {
      return const EmptyState(message: 'Sessão encerrada. Entre novamente.');
    }
    final uid = widget.preview ? 'preview-self' : user!.id;
    final author = widget.authorId ?? (widget.ownOnly ? uid : null);
    final visible = author == null
        ? posts
        : posts.where((p) => p.userId == author).toList();
    if (busy) return const FeedSkeleton();
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(message: error!, icon: Icons.cloud_off),
            FilledButton(
              onPressed: load,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (!widget.ownOnly && widget.authorId == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DESCOBRIR & CONECTAR',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ConexiaColors.brand,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'Para você',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.8,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(
                        child: StatusPill(
                          label: 'Conexões seguras',
                          positive: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ideias que inspiram. Pessoas que aproximam.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!widget.preview && user!.needsGuardian)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.family_restroom_outlined),
                title: const Text(
                  'Acompanhamento familiar',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text('Veja o que seu responsável acompanha.'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FamilyActivityScreen(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (storyError != null)
              TextButton.icon(
                onPressed: load,
                icon: const Icon(Icons.refresh),
                label: Text(storyError!),
              ),
            SizedBox(
              height: 96 + MediaQuery.textScalerOf(context).scale(12) * 1.6,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  StoryAvatar(
                    label: 'Seu story',
                    add: true,
                    ring: false,
                    onTap: () => create(true),
                  ),
                  ...stories.map(
                    (s) => StoryAvatar(
                      label: s.author,
                      image: s.assetImage == null
                          ? null
                          : AssetImage(s.assetImage!),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => StoryViewer(
                            stories: stories,
                            initial: stories.indexOf(s),
                            preview: widget.preview,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PressFeedback(
              child: SurfaceCard(
                margin: const EdgeInsets.only(bottom: 24),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: ConexiaColors.lavender,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      LucideIcons.pencil,
                      size: 20,
                      color: ConexiaColors.brand,
                    ),
                  ),
                  title: const Text(
                    'Compartilhe uma ideia…',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Uma descoberta pode virar uma boa conversa.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(
                    LucideIcons.imagePlus,
                    color: ConexiaColors.brand,
                    size: 23,
                  ),
                  onTap: () => create(false),
                ),
              ),
            ),
          ],
          if (visible.isEmpty)
            const EmptyState(
              message: 'Ainda não há publicações visíveis. Crie a primeira ou conecte-se a um contato aprovado.',
            ),
          ...visible.map((p) {
            final card = SocialPostCard(
              key: ValueKey(p.id),
              post: p,
              own: p.userId == uid,
              preview: widget.preview,
              onProfile: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => UserProfileScreen(
                    userId: p.userId,
                    store: widget.preview
                        ? (widget.previewStore ?? PreviewStore())
                        : null,
                  ),
                ),
              ),
              onDiscuss: !widget.preview && user!.needsGuardian
                  ? () async {
                      try {
                        await AppScope.of(context).api.request(
                          'POST',
                          '/family/discussions',
                          {'post': p.id},
                        );
                        if (context.mounted) {
                          showFeedback(
                            context,
                            'Marcado para conversar com seu responsável.',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) showFeedback(context, e);
                      }
                    }
                  : null,
              onAction: (value) => action(p, value),
              onComment: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CommentsScreen(
                    post: p,
                    preview: widget.preview,
                    previewStore: widget.previewStore,
                  ),
                ),
              ),
              onShare: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Compartilhar referência'),
                  content: SelectableText(
                    '${p.id}\n\nA referência não concede acesso a uma publicação privada.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              ),
            );
            if (!widget.preview && user!.needsGuardian) {
              return PostExposure(
                key: ValueKey('exposure-${p.id}'),
                onDisplayed: () async {
                  await AppScope.of(context).api.request(
                    'POST',
                    '/posts/${p.id}/view',
                    {'visibleMs': 2000},
                  );
                },
                child: card,
              );
            }
            return card;
          }),
          if (cursor != null)
            TextButton(
              onPressed: more ? null : () => load(append: true),
              child: Text(more ? 'Carregando…' : 'Carregar mais'),
            ),
        ],
      ),
    );
  }
}

class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.stories,
    required this.initial,
    this.preview = false,
  });
  final List<Publication> stories;
  final int initial;
  final bool preview;
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late PageController controller;
  @override
  void initState() {
    super.initState();
    controller = PageController(initialPage: widget.initial);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF151722),
    appBar: AppBar(
      backgroundColor: const Color(0xFF151722),
      foregroundColor: Colors.white,
      title: const Text(
        'Stories',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    body: ContentFrame(
      width: 620,
      child: PageView(
        controller: controller,
        children: widget.stories
            .map(
              (p) => SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundImage: p.assetImage == null
                                  ? null
                                  : AssetImage(p.assetImage!),
                              child: p.assetImage == null
                                  ? const Icon(Icons.person_outline)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.author,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Text(
                              '24 h',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * .5,
                        child:
                            p.expires != null &&
                                p.expires! * 1000 <=
                                    DateTime.now().millisecondsSinceEpoch
                            ? const EmptyState(message: 'Este story expirou.')
                            : p.photos.isNotEmpty
                            ? PostPhotoView(
                                photo: p.photos.first,
                                fit: BoxFit.contain,
                              )
                            : SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    p.text,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            if (p.photos.isNotEmpty)
                              Text(
                                p.text,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Deslize para ver o próximo',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Denunciar story',
                                  color: Colors.white,
                                  onPressed: () {
                                    if (widget.preview) {
                                      showFeedback(
                                        context,
                                        'Demonstração: nenhuma denúncia foi enviada.',
                                      );
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              DenunciaScreen(target: p.id),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.flag_outlined),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}

class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.post,
    this.preview = false,
    this.previewStore,
  });
  final Publication post;
  final PreviewStore? previewStore;
  final bool preview;
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final text = TextEditingController();
  int revision = 0;
  final List<Map<String, dynamic>> previewComments = [
    {
      'id': 'preview-comment',
      'name': 'Lia • demonstração',
      'text': 'Vamos criar juntos!',
    },
  ];
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || text.text.trim().isEmpty) return;
    final submitted = text.text;
    if (widget.preview) {
      if (text.text.trim().isEmpty) return;
      if (widget.previewStore != null) {
        widget.previewStore!.comment(widget.post.id, text.text.trim());
        setState(() {
          text.clear();
          revision++;
        });
        return;
      }
      setState(() {
        previewComments.add({
          'id': 'preview-$revision',
          'name': 'Você • demonstração',
          'text': text.text.trim(),
        });
        text.clear();
        revision++;
      });
      return;
    }
    setState(() => busy = true);
    try {
      await AppScope.of(context).api.request(
        'POST',
        '/posts/${widget.post.id}/comments',
        {'text': submitted},
      );
      if (mounted) {
        setState(() {
          if (text.text == submitted) text.clear();
          revision++;
        });
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Comentários')),
    body: ContentFrame(
      child: Column(
        children: [
          Expanded(
            child: AsyncItems(
              key: ValueKey(revision),
              load: () => widget.preview
                  ? Future.value(
                      List<Map<String, dynamic>>.of(
                        widget.previewStore?.comments[widget.post.id] ??
                            previewComments,
                      ),
                    )
                  : AppScope.of(context).social
                        .list('/posts/${widget.post.id}/comments'),
              builder: (_, v) => ListTile(
                title: Text(v['name'] as String),
                subtitle: Text(v['text'] as String),
                trailing: IconButton(
                  tooltip: 'Denunciar comentário',
                  onPressed: () {
                    if (widget.preview) {
                      showFeedback(
                        context,
                        'Demonstração: nenhuma denúncia foi enviada.',
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              DenunciaScreen(target: v['id'] as String),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.flag_outlined),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: text,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Comentário respeitoso',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Enviar comentário',
                    onPressed: busy ? null : send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
