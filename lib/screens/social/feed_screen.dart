import '../../models/preview_content.dart';
import '../../widgets/social/story_avatar.dart';
import '../../widgets/social/social_post_card.dart';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../denuncia_screen.dart';
import 'composer_screen.dart';
import 'private_image.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.ownOnly = false, this.preview = false});
  final bool ownOnly;
  final bool preview;
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}
class _FeedScreenState extends State<FeedScreen> {
  List<Publication> posts = [], stories = [];
  bool busy = true, more = false;
  bool initialized = false;
  bool initializedPreview = false;
  double? cursor;
  String? error;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); if (!initialized) { initialized = true; load(); } }
  Future<void> load({bool append = false}) async {
    if (widget.preview) {
      if (!initializedPreview) {
        initializedPreview = true;
        posts = List.of(previewPublications);
        stories = previewPublications.map((p) => Publication(
          id: 'story-${p.id}', userId: p.userId, author: p.author,
          text: p.text, likes: 0, liked: false, assetImage: p.assetImage,
          expires: DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch / 1000,
        )).toList();
      }
      setState(() { busy = false; error = null; cursor = null; });
      return;
    }
    setState(() { if (append) { more = true; } else { busy = true; } error = null; });
    try {
      final state = AppScope.of(context);
      final result = await state.social.feed(cursor: append ? cursor : null);
      final storyResult = append ? null : await state.social.feed(stories: true);
      if (mounted) setState(() { posts = append ? [...posts,...result.items] : result.items; cursor = result.cursor; if (storyResult != null) stories = storyResult.items; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() { busy = false; more = false; }); }
  }
  Future<void> create(bool story) async {
    if (widget.preview) {
      final controller = TextEditingController();
      final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: Text(story ? 'Story de demonstração' : 'Publicação de demonstração'),
        content: TextField(controller: controller, maxLength: 2000, maxLines: 4, decoration: const InputDecoration(labelText: 'Texto para a prévia local')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim()); }, child: const Text('Adicionar à prévia'))],
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.dispose();
      if (value != null && mounted) setState(() {
        final item = Publication(id: 'preview-${DateTime.now().microsecondsSinceEpoch}', userId: 'preview-self', author: 'Você • demonstração', text: value, likes: 0, liked: false);
        if (story) { stories = [item, ...stories]; } else { posts = [item, ...posts]; }
      });
      return;
    }
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ComposerScreen(story: story)));
    if (result == true && mounted) load();
  }
  Future<void> action(Publication post, String value) async {
    if (widget.preview) {
      if (value == 'like') {
        setState(() => posts = posts.map((p) => p.id != post.id ? p : Publication(id: p.id, userId: p.userId, author: p.author, text: p.text, likes: p.likes + (p.liked ? -1 : 1), liked: !p.liked, media: p.media, expires: p.expires, assetImage: p.assetImage)).toList());
      } else if (value == 'delete' || value == 'block') {
        setState(() => posts.removeWhere((p) => value == 'delete' ? p.id == post.id : p.userId == post.userId));
        showFeedback(context, 'Simulação local aplicada. Nenhum dado foi alterado no servidor.');
      } else {
        showFeedback(context, 'Prévia local: esta ação exige uma conta verificada no aplicativo real.');
      }
      return;
    }
    if (value == 'report') { await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => DenunciaScreen(target: post.id))); return; }
    if (value == 'edit') { final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ComposerScreen(postId: post.id, initialText: post.text))); if (result == true && mounted) load(); return; }
    try {
      if (value == 'delete' || value == 'block') {
        final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(value == 'delete' ? 'Excluir publicação?' : 'Bloquear este perfil?'), content: Text(value == 'delete' ? 'Esta ação remove a publicação e seus comentários.' : 'O bloqueio impede visibilidade e novas interações entre os perfis.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar'))]));
        if (confirm != true || !mounted) return;
      }
      final api = AppScope.of(context).api;
      if (value == 'like') await api.request('POST','/posts/${post.id}/like');
      if (value == 'delete') await api.request('DELETE','/posts/${post.id}');
      if (value == 'block') await api.request('POST','/blocks', {'target': post.userId});
      if (mounted) load();
    } catch (e) { if (mounted) showFeedback(context,e); }
  }
  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).account;
    if (user == null && !widget.preview) return const EmptyState(message: 'Sessão encerrada. Entre novamente.');
    final uid = widget.preview ? 'preview-self' : user!.id;
    final visible = widget.ownOnly ? posts.where((p) => p.userId == uid).toList() : posts;
    if (busy) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [EmptyState(message: error!, icon: Icons.cloud_off), FilledButton(onPressed: load, child: const Text('Tentar novamente'))]));
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (!widget.ownOnly) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                const Text('Para você', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                const Spacer(),
                const Icon(Icons.verified_user_outlined, size: 15, color: Color(0xFF278F7D)),
                const SizedBox(width: 5),
                const Text('Conexões seguras', style: TextStyle(fontSize: 11, color: Color(0xFF278F7D))),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 110,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                StoryAvatar(label: 'Seu story', add: true, ring: false, onTap: () => create(true)),
                ...stories.map((s) => StoryAvatar(
                  label: s.author,
                  image: s.assetImage == null ? null : AssetImage(s.assetImage!),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => StoryViewer(stories: stories, initial: stories.indexOf(s), preview: widget.preview),
                  )),
                )),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE9EAF0))),
              child: ListTile(
                leading: const CircleAvatar(radius: 18, backgroundColor: Color(0xFFEBEDFC), child: Icon(Icons.edit_outlined, size: 19, color: Color(0xFF5658D9))),
                title: const Text('Compartilhe uma ideia…', style: TextStyle(fontSize: 14, color: Color(0xFF858794))),
                trailing: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF5658D9)),
                onTap: () => create(false),
              ),
            ),
          ],
          if (visible.isEmpty) const EmptyState(message: 'Ainda não há publicações visíveis. Crie a primeira ou conecte-se a um contato aprovado.'),
          ...visible.map((p) => SocialPostCard(
            key: ValueKey(p.id), post: p, own: p.userId == uid, preview: widget.preview,
            onAction: (value) => action(p, value),
            onComment: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CommentsScreen(post: p, preview: widget.preview))),
            onShare: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
              title: const Text('Compartilhar referência'),
              content: SelectableText('${p.id}\n\nA referência não concede acesso a uma publicação privada.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
            )),
          )),
          if (cursor != null) TextButton(onPressed: more ? null : () => load(append: true), child: Text(more ? 'Carregando…' : 'Carregar mais')),
        ],
      ),
    );
  }
}

class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.stories, required this.initial, this.preview = false});
  final List<Publication> stories;
  final int initial;
  final bool preview;
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}
class _StoryViewerState extends State<StoryViewer> {
  late PageController controller;
  @override
  void initState() { super.initState(); controller = PageController(initialPage: widget.initial); }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF151722),
    appBar: AppBar(backgroundColor: const Color(0xFF151722), foregroundColor: Colors.white, title: const Text('Stories', style: TextStyle(fontWeight: FontWeight.w700))),
    body: ContentFrame(width: 620, child: PageView(
      controller: controller,
      children: widget.stories.map((p) => SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: Row(children: [
          CircleAvatar(radius: 18, backgroundImage: p.assetImage == null ? null : AssetImage(p.assetImage!), child: p.assetImage == null ? const Icon(Icons.person_outline) : null),
          const SizedBox(width: 10),
          Expanded(child: Text(p.author, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          const Text('24 h', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ])),
        Expanded(child: p.expires != null && p.expires! * 1000 <= DateTime.now().millisecondsSinceEpoch
          ? const EmptyState(message: 'Este story expirou.')
          : p.assetImage != null
            ? Image.asset(p.assetImage!, fit: BoxFit.contain, semanticLabel: 'Story de ${p.author}')
            : p.media != null ? PrivateImage(media: p.media!, height: 420)
              : Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(p.text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24)))),
        ),
        Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          if (p.assetImage != null) Text(p.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Deslize para ver o próximo', style: TextStyle(color: Colors.white60, fontSize: 12))),
            IconButton(tooltip: 'Denunciar story', color: Colors.white, onPressed: () {
              if (widget.preview) { showFeedback(context, 'Demonstração: nenhuma denúncia foi enviada.'); }
              else { Navigator.push(context, MaterialPageRoute<void>(builder: (_) => DenunciaScreen(target: p.id))); }
            }, icon: const Icon(Icons.flag_outlined)),
          ]),
        ])),
      ]))).toList(),
    )),
  );
}

class CommentsScreen extends StatefulWidget {
  const CommentsScreen({super.key, required this.post, this.preview = false});
  final Publication post;
  final bool preview;
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}
class _CommentsScreenState extends State<CommentsScreen> {
  final text = TextEditingController();
  int revision = 0;
  final List<Map<String, dynamic>> previewComments = [{'id': 'preview-comment', 'name': 'Lia • demonstração', 'text': 'Vamos criar juntos!'}];
  bool busy = false;
  @override
  void dispose() { text.dispose(); super.dispose(); }
  Future<void> send() async {
    if (widget.preview) {
      if (text.text.trim().isEmpty) return;
      setState(() { previewComments.add({'id': 'preview-$revision', 'name': 'Você • demonstração', 'text': text.text.trim()}); text.clear(); revision++; });
      return;
    }
    setState(() => busy = true);
    try { await AppScope.of(context).api.request('POST','/posts/${widget.post.id}/comments',{'text': text.text}); if (mounted) setState(() { text.clear(); revision++; }); }
    catch (e) { if (mounted) showFeedback(context,e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Comentários')), body: ContentFrame(child: Column(children: [Expanded(child: AsyncItems(key: ValueKey(revision), load: () => widget.preview ? Future.value(List<Map<String, dynamic>>.of(previewComments)) : AppScope.of(context).social.list('/posts/${widget.post.id}/comments'), builder: (_,v) => ListTile(title: Text(v['name'] as String), subtitle: Text(v['text'] as String), trailing: IconButton(tooltip: 'Denunciar comentário', onPressed: () { if (widget.preview) { showFeedback(context, 'Demonstração: nenhuma denúncia foi enviada.'); } else { Navigator.push(context, MaterialPageRoute<void>(builder: (_) => DenunciaScreen(target: v['id'] as String))); } }, icon: const Icon(Icons.flag_outlined))))), SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: TextField(controller: text, maxLength: 500, decoration: const InputDecoration(labelText: 'Comentário respeitoso'))), IconButton(tooltip: 'Enviar comentário', onPressed: busy ? null : send, icon: const Icon(Icons.send))])))])));
}
