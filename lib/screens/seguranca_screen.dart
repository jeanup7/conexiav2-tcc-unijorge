import 'contact_requests_screen.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/common.dart';

class SegurancaScreen extends StatefulWidget {
  const SegurancaScreen({super.key});
  @override
  State<SegurancaScreen> createState() => _SegurancaScreenState();
}

class _SegurancaScreenState extends State<SegurancaScreen> {
  final name = TextEditingController(), bio = TextEditingController();
  bool initialized = false, private = true, messages = false, busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      final u = AppScope.of(context).account;
      if (u == null) return;
      name.text = u.name;
      bio.text = u.bio;
      private = u.private;
      messages = u.messages;
      initialized = true;
    }
  }

  @override
  void dispose() {
    name.dispose();
    bio.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final state = AppScope.of(context);
      final version = state.api.sessionVersion;
      await state.api.request('PATCH', '/me', {
        'name': name.text,
        'bio': bio.text,
        'private': private,
        'messages': messages,
      });
      state.api.checkSession(version);
      await state.reloadAccount();
      state.social.invalidate();
      if (mounted) showFeedback(context, 'Preferências salvas no servidor.');
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    try {
      final result = await AppScope.of(context).api
          .request('GET', '/me/export');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seus dados'),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(result),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showFeedback(context, e);
    }
  }

  Future<void> delete() async {
    if (busy) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || !mounted || busy) return;
    setState(() => busy = true);
    try {
      final state = AppScope.of(context);
      await state.deleteAccount(password);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).account;
    if (user == null) {
      return const Scaffold(body: EmptyState(message: 'Sessão encerrada.'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidade e segurança')),
      body: ContentFrame(
        width: 620,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Você está no controle',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Apelido'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bio,
              maxLength: 180,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Biografia (sem informações pessoais)',
              ),
            ),
            SwitchListTile(
              title: const Text('Perfil privado'),
              subtitle: Text(
                user.needsGuardian
                    ? 'Obrigatório para menores neste projeto.'
                    : 'Somente contatos aprovados veem suas publicações.',
              ),
              value: private,
              onChanged: user.needsGuardian || busy
                  ? null
                  : (v) => setState(() => private = v),
            ),
            SwitchListTile(
              title: const Text('Mensagens de contatos aprovados'),
              subtitle: const Text(
                'Desconhecidos nunca podem iniciar conversas.',
              ),
              value: messages,
              onChanged: busy ? null : (v) => setState(() => messages = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Salvando…' : 'Salvar preferências'),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Pessoas bloqueadas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const BlocksScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Minhas denúncias'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Pedidos de contato'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ContactRequestsScreen(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.family_restroom),
              title: const Text('Situação do vínculo familiar'),
              onTap: () => Navigator.pushNamed(context, '/painel-responsavel'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Consultar e copiar meus dados'),
              onTap: busy ? null : export,
            ),
            const ListTile(
              leading: Icon(Icons.accessibility_new),
              title: Text('Acessibilidade'),
              subtitle: Text(
                'Compatível com escala de texto e leitor de tela. Transições respeitam a preferência do sistema por reduzir animações.',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.face_outlined),
              title: Text('Verificação facial'),
              subtitle: Text(
                'Desativada. Nenhuma câmera, imagem facial ou dado biométrico é coletado.',
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        final warning = await AppScope.of(context).logout();
                        if (context.mounted) {
                          if (warning != null) showFeedback(context, warning);
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/login',
                            (_) => false,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) showFeedback(context, e);
                      }
                    },
              icon: const Icon(Icons.logout),
              label: const Text('Sair da conta'),
            ),
            TextButton(
              onPressed: busy ? null : delete,
              child: Text(
                'Excluir minha conta',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BlocksScreen extends StatefulWidget {
  const BlocksScreen({super.key});
  @override
  State<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends State<BlocksScreen> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bloqueados')),
    body: ContentFrame(
      child: AsyncItems(
        key: ValueKey(revision),
        load: () => AppScope.of(context).social.list('/blocks'),
        builder: (_, v) => ListTile(
          title: Text(v['name'] as String),
          trailing: TextButton(
            onPressed: () async {
              try {
                await AppScope.of(context).api
                    .request('DELETE', '/blocks/${v['id']}');
                if (mounted && context.mounted) {
                  AppScope.of(context).social.invalidate();
                  setState(() => revision++);
                }
              } catch (e) {
                if (context.mounted) showFeedback(context, e);
              }
            },
            child: const Text('Desbloquear'),
          ),
        ),
      ),
    ),
  );
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Minhas denúncias')),
    body: ContentFrame(
      child: AsyncItems(
        load: () => AppScope.of(context).social.list('/reports'),
        builder: (_, v) => ListTile(
          title: Text(v['reason'] as String),
          subtitle: Text('Protocolo: ${v['id']}\nStatus: ${v['status']}'),
        ),
      ),
    ),
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final password = TextEditingController();
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Excluir conta permanentemente?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Publicações, mensagens, mídias e dados da conta serão removidos. Confirme sua senha.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, password.text),
        child: const Text('Excluir conta'),
      ),
    ],
  );
}
