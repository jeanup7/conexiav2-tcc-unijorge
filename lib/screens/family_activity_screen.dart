import 'package:flutter/material.dart';

import '../widgets/common.dart';
import '../widgets/social/post_gallery.dart';
import '../models/models.dart';
import '../models/content_categories.dart';

class FamilyActivityScreen extends StatefulWidget {
  const FamilyActivityScreen({super.key, this.childId, this.childName});
  final String? childId, childName;
  @override
  State<FamilyActivityScreen> createState() => _FamilyActivityState();
}

class _FamilyActivityState extends State<FamilyActivityScreen> {
  int days = 7, section = 0;
  Future<Map<String, dynamic>>? future;
  bool get parent => widget.childId != null;
  String get base =>
      parent ? '/guardian/children/${widget.childId}' : '/family';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= fetch();
  }

  Future<Map<String, dynamic>> fetch() =>
      AppScope.of(context).api.request('GET', '$base/activity?days=$days');
  void reload() => setState(() {
    future = fetch();
  });
  Future<void> discuss(Map<String, dynamic> post) async {
    try {
      await AppScope.of(context).api
          .request('POST', '$base/discussions', {'post': post['id']});
      if (mounted) {
        reload();
        showFeedback(context, 'Publicação marcada para conversar em família.');
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    }
  }

  Future<void> resolve(Map<String, dynamic> topic) async {
    try {
      await AppScope.of(context).api.request(
        'PATCH',
        '/family/discussions/${topic['id']}',
        {'state': topic['state'] == 'open' ? 'resolved' : 'open'},
      );
      if (mounted) reload();
    } catch (e) {
      if (mounted) showFeedback(context, e);
    }
  }

  void detail(Map<String, dynamic> post) {
    final photos = (post['mediaItems'] as List)
        .map(
          (id) => PostPhoto.remote(
            id as String,
            endpoint: '$base/activity/posts/${post['id']}/media/$id',
          ),
        )
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Publicação acompanhada')),
          body: ContentFrame(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  (post['author'] as Map)['name'] as String,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(contentCategories[post['category']] ?? 'Outros'),
                const SizedBox(height: 16),
                if (photos.isNotEmpty)
                  PostGallery(photos: photos, onDoubleTap: () {}),
                const SizedBox(height: 16),
                Text(post['text'] as String),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => discuss(post),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Vamos conversar?'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A publicação pode deixar de aparecer se for excluída ou se as permissões de acesso mudarem.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String date(dynamic seconds) {
    final d = DateTime.fromMillisecondsSinceEpoch(
      ((seconds as num) * 1000).round(),
    ).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} às ${two(d.hour)}:${two(d.minute)}';
  }

  Widget postTile(Map<String, dynamic> row, {bool topic = false}) {
    final post = row['post'] as Map<String, dynamic>?;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(topic ? Icons.forum_outlined : Icons.photo_outlined),
            title: Text(
              post == null
                  ? 'Publicação indisponível'
                  : (post['author'] as Map)['name'] as String,
            ),
            subtitle: Text(
              topic
                  ? '${row['requestedBy'] == 'child' ? 'Marcada pelo menor' : 'Marcada pelo responsável'} • ${row['state'] == 'open' ? 'Para conversar' : 'Conversamos'}'
                  : '${contentCategories[row['category']] ?? 'Outros'} • ${date(row['seenAt'])}',
            ),
            trailing: post == null ? null : const Icon(Icons.chevron_right),
            onTap: post == null ? null : () => detail(post),
          ),
          if (post != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                post['text'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (topic)
            TextButton(
              onPressed: () => resolve(row),
              child: Text(
                row['state'] == 'open'
                    ? 'Marcar como conversamos'
                    : 'Reabrir conversa',
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        parent
            ? 'Feed de ${widget.childName ?? 'seu familiar'}'
            : 'O que meu responsável vê',
      ),
    ),
    body: ContentFrame(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyState(message: snapshot.error.toString()),
                  TextButton(
                    onPressed: reload,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done ||
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final categories = data['categories'] as List;
          final history = data['history'] as List;
          final discussions = data['discussions'] as List;
          return RefreshIndicator(
            onRefresh: () async {
              reload();
              try {
                await future;
              } catch (_) {
                // FutureBuilder presents the error and retry action.
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  parent
                      ? 'Acompanhe e converse'
                      : 'O acompanhamento é compartilhado',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  parent
                      ? 'Um ponto de partida para conversar sobre o feed de ${data['child']['name']}.'
                      : 'Você e seu responsável têm acesso ao mesmo resumo, histórico e publicações marcadas para conversar.',
                ),
                const SizedBox(height: 12),
                Text(data['notice'] as String),
                const SizedBox(height: 8),
                const Text(
                  'Histórico por até 30 dias. A lista mostra os 50 registros mais recentes do período. Este acompanhamento inclui as publicações do feed, não os recortes.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in [7, 30])
                      ChoiceChip(
                        label: Text('$value dias'),
                        selected: days == value,
                        onSelected: (_) {
                          days = value;
                          reload();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Resumo')),
                    ButtonSegment(value: 1, label: Text('Posts')),
                    ButtonSegment(value: 2, label: Text('Conversar')),
                  ],
                  selected: {section},
                  onSelectionChanged: (v) => setState(() => section = v.first),
                ),
                const SizedBox(height: 16),
                if (section == 0) ...[
                  Text(
                    '${data['total']} registros de exibição',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Repetições da mesma publicação no mesmo dia contam uma vez. As categorias são escolhidas pelo autor.',
                  ),
                  if (categories.isEmpty)
                    const EmptyState(
                      message:
                          'As categorias aparecem conforme o feed é navegado.',
                    ),
                  for (final raw in categories)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('${raw['name']} • ${raw['count']}'),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value:
                                  (raw['count'] as num) /
                                  (data['total'] as num),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (section == 1) ...[
                  if (history.isEmpty)
                    const EmptyState(
                      message: 'Ainda não há posts registrados neste período.',
                    ),
                  ...history.map(
                    (v) => postTile(Map<String, dynamic>.from(v as Map)),
                  ),
                ],
                if (section == 2) ...[
                  const Text(
                    'As marcações ficam disponíveis até serem removidas com a conta. O período acima filtra apenas o histórico de exibição.',
                  ),
                  if (discussions.isEmpty)
                    const EmptyState(
                      message: 'Marque uma publicação com “Vamos conversar?” para começar.',
                    ),
                  ...discussions.map(
                    (v) => postTile(
                      Map<String, dynamic>.from(v as Map),
                      topic: true,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
