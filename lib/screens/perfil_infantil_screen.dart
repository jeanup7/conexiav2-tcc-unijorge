import 'package:flutter/material.dart';
import '../widgets/common.dart';
import 'social/feed_screen.dart';

class PerfilInfantilScreen extends StatelessWidget {
  const PerfilInfantilScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).account;
    if (user == null) return const EmptyState(message: 'Entre para ver seu perfil.');
    final body = Column(children: [Padding(padding: const EdgeInsets.all(24), child: Column(children: [const CircleAvatar(radius: 38, child: Icon(Icons.person_outline, size: 42)), const SizedBox(height: 12), Text(user.name, style: Theme.of(context).textTheme.headlineSmall), Text(user.private ? 'Perfil privado' : 'Perfil público'), if (user.bio.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(user.bio)), TextButton.icon(onPressed: () => Navigator.pushNamed(context,'/seguranca'), icon: const Icon(Icons.edit_outlined), label: const Text('Editar perfil e preferências'))])), const Expanded(child: FeedScreen(ownOnly: true))]);
    return embedded ? body : Scaffold(appBar: AppBar(title: const Text('Meu perfil')), body: ContentFrame(child: body));
  }
}
