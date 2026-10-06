import 'social/feed_preview_screen.dart';
import 'package:flutter/material.dart';
import '../widgets/common.dart';
import 'social/feed_screen.dart';
import 'social/messages_screen.dart';
import 'social/search_screen.dart';
import 'perfil_infantil_screen.dart';
import 'verification_screen.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});
  @override
  State<InicioScreen> createState() => _InicioScreenState();
}
class _InicioScreenState extends State<InicioScreen> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.account;
    if (user == null) return const Scaffold(body: Center(child: Text('Sessão encerrada. Volte ao login.')));
    final pages = <Widget>[const FeedScreen(), const SearchScreen(), const MessagesScreen(), const PerfilInfantilScreen(embedded: true)];
    return Scaffold(appBar: AppBar(centerTitle: true, title: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shield_rounded, color: Color(0xFF4965E8)), SizedBox(width: 8), Text('Conexia', style: TextStyle(fontWeight: FontWeight.w800))]), actions: [IconButton(tooltip: 'Notificações', onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())), icon: const Icon(Icons.notifications_outlined)), IconButton(tooltip: 'Privacidade e segurança', onPressed: () => Navigator.pushNamed(context,'/seguranca'), icon: const Icon(Icons.shield_outlined))]),
      body: ContentFrame(child: !user.active ? ListView(padding: const EdgeInsets.all(24), children: [Text('Bem-vindo, ${user.name}', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 20), if (FeedPreviewScreen.available) ...[FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const FeedPreviewScreen())), icon: const Icon(Icons.visibility_outlined), label: const Text('Ver prévia do feed')), const SizedBox(height: 16)], const EmptyState(message: 'Vamos concluir as verificações antes de liberar publicações, pesquisa e mensagens.', icon: Icons.shield_outlined), if (!user.verified) FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const VerificationScreen())), child: const Text('Confirmar e-mail')), if (user.needsGuardian && !user.approved) ...[const SizedBox(height: 12), OutlinedButton(onPressed: () => Navigator.pushNamed(context,'/painel-responsavel'), child: const Text('Ver situação do vínculo familiar'))], TextButton(onPressed: () async { try { await state.reloadAccount(); } catch (e) { if (context.mounted) showFeedback(context,e); } }, child: const Text('Atualizar verificações')), TextButton(onPressed: () => Navigator.pushNamed(context,'/seguranca'), child: const Text('Gerenciar conta e dados'))]) : AnimatedSwitcher(duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180), child: KeyedSubtree(key: ValueKey(selected), child: pages[selected]))),
      bottomNavigationBar: user.active ? NavigationBar(selectedIndex: selected, onDestinationSelected: (v) => setState(() => selected = v), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Feed'), NavigationDestination(icon: Icon(Icons.search), label: 'Pesquisa'), NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Mensagens'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil')]) : null);
  }
}
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Notificações')), body: ContentFrame(child: AsyncItems(load: () => AppScope.of(context).social.list('/notifications'), builder: (_,v) => ListTile(leading: const Icon(Icons.notifications_outlined), title: Text(v['text'] as String)))));
}
