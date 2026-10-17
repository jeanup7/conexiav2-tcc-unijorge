import '../widgets/design_system.dart';
import 'nickname_setup.dart';
import 'social/feed_preview_screen.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/common.dart';
import 'social/feed_screen.dart';
import 'social/messages_screen.dart';
import 'social/search_screen.dart';
import 'perfil_infantil_screen.dart';
import 'verification_screen.dart';
import 'admin_screen.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});
  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  int selected = 0;
  final visited = <int>{0};
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.account;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sessão encerrada. Volte ao login.')),
      );
    }
    final pages = <Widget>[
      const FeedScreen(),
      const SearchScreen(),
      const MessagesScreen(),
      const PerfilInfantilScreen(embedded: true),
    ];
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const BrandMark(compact: true),
        actions: [
          if (user.isAdmin)
            IconButton(
              tooltip: 'Administração',
              icon: const Icon(LucideIcons.settings),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AdminScreen()),
              ),
            ),
          IconButton(
            tooltip: user.needsGuardian ? 'Meu responsável' : 'Minha família',
            icon: const Icon(Icons.family_restroom_outlined),
            onPressed: () =>
                Navigator.pushNamed(context, '/painel-responsavel'),
          ),
          IconButton(
            tooltip: 'Notificações',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
            icon: const Icon(LucideIcons.bell),
          ),
          IconButton(
            tooltip: 'Privacidade e segurança',
            onPressed: () => Navigator.pushNamed(context, '/seguranca'),
            icon: const Icon(LucideIcons.shieldCheck),
          ),
        ],
      ),
      body: ContentFrame(
        child: user.accountStatus == 'suspended'
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const EmptyState(
                    message: 'Esta conta está suspensa. Você pode consultar seus dados e gerenciar sua conta em Privacidade e segurança.',
                    icon: Icons.pause_circle_outline,
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pushNamed(context, '/seguranca'),
                    child: const Text('Gerenciar conta e dados'),
                  ),
                ],
              )
            : user.verified && user.approved && user.needsNickname
            ? const NicknameSetup()
            : !user.active
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Bem-vindo, ${user.name}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  if (FeedPreviewScreen.available) ...[
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const FeedPreviewScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Ver prévia do feed'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const EmptyState(
                    message: 'Vamos concluir as verificações antes de liberar publicações, pesquisa e mensagens.',
                    icon: LucideIcons.shieldCheck,
                  ),
                  if (!user.verified)
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const VerificationScreen(),
                        ),
                      ),
                      child: const Text('Confirmar e-mail'),
                    ),
                  if (user.needsGuardian && !user.approved) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/painel-responsavel'),
                      child: const Text('Ver situação do vínculo familiar'),
                    ),
                  ],
                  TextButton(
                    onPressed: () async {
                      try {
                        await state.reloadAccount();
                      } catch (e) {
                        if (context.mounted) showFeedback(context, e);
                      }
                    },
                    child: const Text('Atualizar verificações'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/seguranca'),
                    child: const Text('Gerenciar conta e dados'),
                  ),
                ],
              )
            : IndexedStack(
                index: selected,
                children: List.generate(
                  pages.length,
                  (index) => TickerMode(
                    enabled: selected == index,
                    child: visited.contains(index)
                        ? pages[index]
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
      ),
      bottomNavigationBar: user.active
          ? NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (v) => setState(() {
                selected = v;
                visited.add(v);
              }),
              destinations: const [
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
            )
          : null,
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notificações')),
    body: ContentFrame(
      child: AsyncItems(
        load: () => AppScope.of(context).social.list('/notifications'),
        builder: (_, v) => ListTile(
          leading: const Icon(LucideIcons.bell),
          title: Text(v['text'] as String),
        ),
      ),
    ),
  );
}
