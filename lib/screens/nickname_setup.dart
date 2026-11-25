import '../widgets/design_system.dart';
import 'vision_screen.dart';

import 'package:flutter/material.dart';

import '../widgets/common.dart';

class NicknameSetup extends StatefulWidget {
  const NicknameSetup({super.key});
  @override
  State<NicknameSetup> createState() => _NicknameState();
}

class _NicknameState extends State<NicknameSetup> {
  final name = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Escolha um apelido.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final state = AppScope.of(context);
      final version = state.api.sessionVersion;
      final user = state.account!;
      await state.api.request('PATCH', '/me', {
        'name': name.text.trim(),
        'bio': user.bio,
        'private': true,
        'messages': user.messages,
      });
      state.api.checkSession(version);
      await state.reloadAccount();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Icon(Icons.auto_awesome_outlined, size: 56),
      const SizedBox(height: 24),
      Text(
        'Como você quer aparecer no feed?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      const Text(
        'Os e-mails estão confirmados. Escolha um apelido para seu perfil e suas publicações.',
      ),
      const SizedBox(height: 20),
      TextField(
        key: const ValueKey('nickname'),
        controller: name,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Seu apelido'),
      ),
      if (error != null) InlineNotice(message: error!, error: true),
      TextButton.icon(
        onPressed: busy
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const VisionScreen()),
              ),
        icon: const Icon(Icons.science_outlined),
        label: const Text('Experimento de faixa etária (opcional)'),
      ),
      const SizedBox(height: 16),
      BusyButton(
        onPressed: save,
        busy: busy,
        label: busy ? 'Salvando…' : 'Salvar apelido e entrar no feed',
      ),
    ],
  );
}
