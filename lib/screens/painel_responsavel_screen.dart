import '../widgets/design_system.dart';
import '../theme/design_tokens.dart';
import 'family_activity_screen.dart';
import 'contact_requests_screen.dart';

import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'child_account_screen.dart';
import 'verification_screen.dart';

class PainelResponsavelScreen extends StatefulWidget {
  const PainelResponsavelScreen({super.key});
  @override
  State<PainelResponsavelScreen> createState() => _FamilyState();
}

class _FamilyState extends State<PainelResponsavelScreen> {
  int revision = 0;
  Future<Map<String, dynamic>>? status;
  final pending = <String>{};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppScope.of(context).account?.needsGuardian == true) {
      status ??= AppScope.of(context).api.request('GET', '/guardian/status');
    }
  }

  void refresh() => setState(() {
    revision++;
    if (AppScope.of(context).account?.needsGuardian == true) {
      status = AppScope.of(context).api.request('GET', '/guardian/status');
    }
  });
  Future<void> change(String id, String state) async {
    if (!pending.add(id)) return;
    setState(() {});
    try {
      await AppScope.of(context).api
          .request('PATCH', '/guardian/children/$id', {'state': state});
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      pending.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.account;
    if (user == null) {
      return const Scaffold(
        body: EmptyState(message: 'Entre para acessar sua família.'),
      );
    }
    final minor = user.needsGuardian;
    return Scaffold(
      appBar: AppBar(
        title: Text(minor ? 'Meu responsável' : 'Minha família'),
        actions: [
          IconButton(
            onPressed: refresh,
            tooltip: 'Atualizar família',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ContentFrame(
        child: HeaderBody(
          header: SurfaceCard(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            gradient: ConexiaColors.hero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: 'Cuidado que aproxima',
                    icon: Icons.family_restroom_outlined,
                    positive: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  minor ? 'Seu vínculo familiar' : 'Perfis vinculados',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  minor
                      ? 'O feed depende da confirmação do seu e-mail, do e-mail do responsável e do vínculo ativo.'
                      : 'Crie o perfil do menor com um e-mail próprio. Ele receberá a confirmação e escolherá seu apelido ao entrar.',
                ),
                if (minor)
                  TextButton.icon(
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('O que meu responsável vê'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FamilyActivityScreen(),
                      ),
                    ),
                  ),
                if (!minor && user.verified) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Criar ou vincular perfil do menor'),
                    onPressed: () async {
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChildAccountScreen(),
                        ),
                      );
                      if (result == true && mounted) {
                        setState(() => revision++);
                      }
                    },
                  ),
                ],
                if (!user.verified)
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VerificationScreen(),
                      ),
                    ),
                    child: const Text('Confirmar meu e-mail'),
                  ),
              ],
            ),
          ),
          body: minor
              ? FutureBuilder<Map<String, dynamic>>(
                  future: status,
                  builder: (_, s) =>
                      s.connectionState != ConnectionState.done || !s.hasData
                      ? Center(
                          child: s.hasError
                              ? Text(s.error.toString())
                              : const CircularProgressIndicator(),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            ListTile(
                              leading: Icon(
                                s.data!['childVerified'] == true
                                    ? Icons.check_circle_outline
                                    : Icons.schedule,
                              ),
                              title: const Text('Seu e-mail confirmado'),
                            ),
                            ListTile(
                              leading: Icon(
                                s.data!['guardianVerified'] == true
                                    ? Icons.check_circle_outline
                                    : Icons.schedule,
                              ),
                              title: Text(
                                s.data!['guardianName'] as String? ??
                                    'Responsável ainda não vinculado',
                              ),
                            ),
                            ListTile(
                              leading: Icon(
                                s.data!['approved'] == true
                                    ? Icons.check_circle_outline
                                    : Icons.schedule,
                              ),
                              title: Text(
                                s.data!['state'] == 'paused'
                                    ? 'Acesso pausado pelo responsável'
                                    : s.data!['approved'] == true
                                    ? 'Vínculo ativo'
                                    : 'Aguardando vínculo',
                              ),
                            ),
                          ],
                        ),
                )
              : !user.verified
              ? const EmptyState(
                  message: 'Confirme seu e-mail antes de cadastrar um menor.',
                )
              : AsyncItems(
                  key: ValueKey(revision),
                  load: () => state.social.list('/guardian/children'),
                  empty: 'Nenhum perfil vinculado. Comece criando o perfil do menor.',
                  builder: (_, v) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v['childName'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('Apelido: ${v["name"]}'),
                          TextButton.icon(
                            icon: const Icon(Icons.people_outline),
                            label: const Text('Autorizar contatos'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ContactRequestsScreen(
                                  childId: v['id'] as String,
                                  childName: v['name'] as String,
                                ),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.insights_outlined),
                            label: const Text('Acompanhar feed'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FamilyActivityScreen(
                                  childId: v['id'] as String,
                                  childName: v['name'] as String,
                                ),
                              ),
                            ),
                          ),
                          Text(v['email'] as String),
                          Text(
                            v['verified'] == 1
                                ? 'E-mail do menor confirmado'
                                : 'Aguardando confirmação do menor',
                          ),
                          if (v['needsNickname'] == true)
                            const Text(
                              'O menor escolherá o apelido ao entrar.',
                            ),
                          TextButton(
                            onPressed: pending.contains(v['id'])
                                ? null
                                : () => change(
                                    v['id'] as String,
                                    v['state'] == 'active'
                                        ? 'paused'
                                        : 'active',
                                  ),
                            child: Text(
                              v['state'] == 'active'
                                  ? 'Pausar acesso'
                                  : 'Reativar acesso',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
