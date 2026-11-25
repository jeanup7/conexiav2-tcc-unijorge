import '../../theme/appearance.dart';
import '../../widgets/social/conexia_compass.dart';
import '../../widgets/design_system.dart';
import '../../theme/design_tokens.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../state/preview_store.dart';
import '../../widgets/common.dart';
import '../../widgets/social/post_gallery.dart';
import 'composer_screen.dart';
import 'feed_screen.dart';
import 'user_profile_screen.dart';

class FeedPreviewScreen extends StatefulWidget {
  const FeedPreviewScreen({super.key});
  static bool get available =>
      kDebugMode &&
      (!kIsWeb || const {'localhost', '127.0.0.1'}.contains(Uri.base.host));
  @override
  State<FeedPreviewScreen> createState() => _FeedPreviewScreenState();
}

class _FeedPreviewScreenState extends State<FeedPreviewScreen> {
  final store = PreviewStore();
  final query = TextEditingController();
  int tab = 0;
  @override
  void dispose() {
    store.dispose();
    query.dispose();
    super.dispose();
  }

  void created(Publication post) {
    store.add(post);
    setState(() => tab = 0);
  }

  Widget search() => Column(
    children: [
      Padding(
        padding: EdgeInsets.all(16),
        child: TextField(
          controller: query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Pesquisar perfis da prévia',
            prefixIcon: Icon(LucideIcons.search),
          ),
        ),
      ),
      Expanded(
        child: AnimatedBuilder(
          animation: store,
          builder: (_, _) {
            final found = store.profiles
                .where(
                  (p) =>
                      p.name.toLowerCase().contains(query.text.toLowerCase()),
                )
                .toList();
            return found.isEmpty
                ? EmptyState(message: 'Nenhum perfil encontrado.')
                : ListView(
                    children: found
                        .map(
                          (p) => ListTile(
                            leading: SizedBox(
                              width: 44,
                              height: 44,
                              child: ClipOval(
                                child: p.photo == null
                                    ? ColoredBox(
                                        color: ConexiaPalette.of(context)
                                            .tinted,
                                        child: Icon(LucideIcons.userRound),
                                      )
                                    : PostPhotoView(photo: p.photo!),
                              ),
                            ),
                            title: Text(p.name),
                            subtitle: Text('Perfil de demonstração'),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => UserProfileScreen(
                                  userId: p.id,
                                  store: store,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
          },
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (!FeedPreviewScreen.available) {
      return Scaffold(
        body: EmptyState(
          message: 'A prévia está disponível apenas no desenvolvimento local.',
        ),
      );
    }
    return Scaffold(
      backgroundColor: ConexiaPalette.of(context).background,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: ConexiaPalette.of(context).surface,
        surfaceTintColor: Colors.transparent,
        title: BrandMark(compact: true),
        actions: [
          IconButton(
            tooltip: 'Aparência',
            icon: const Icon(Icons.contrast),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) =>
                  const SingleChildScrollView(child: AppearanceControl()),
            ),
          ),
          IconButton(
            tooltip: 'Sobre a prévia',
            icon: Icon(LucideIcons.info),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Prévia local'),
                content: Text(
                  'Perfis, fotos e interações são de demonstração. Alterações permanecem entre as abas, mas são descartadas quando você sai da prévia. Nenhuma chamada ao servidor é feita.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Entendi'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ContentFrame(
        width: 600,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: ConexiaPalette.of(context).tinted,
              child: Text(
                'PRÉVIA LOCAL • Conteúdo de demonstração',
                style: TextStyle(
                  fontSize: 11,
                  color: ConexiaPalette.of(context).primary,
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [
                  FeedScreen(preview: true, previewStore: store),
                  search(),
                  Center(
                    child: EmptyState(
                      message: 'Conversas reais ficam no aplicativo autenticado. Esta prévia não envia mensagens.',
                      icon: LucideIcons.messageCircle,
                    ),
                  ),
                  UserProfileScreen(
                    userId: 'preview-self',
                    store: store,
                    embedded: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Criar publicação',
        onPressed: () async {
          final post = await Navigator.push<Publication>(
            context,
            MaterialPageRoute<Publication>(
              builder: (_) => const ComposerScreen(preview: true),
            ),
          );
          if (mounted && post != null) created(post);
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: ConexiaCompass(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(
            icon: Icon(LucideIcons.house),
            selectedIcon: Icon(LucideIcons.house),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.search),
            label: 'Pesquisa',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.messageCircle),
            label: 'Mensagens',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.userRound),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
