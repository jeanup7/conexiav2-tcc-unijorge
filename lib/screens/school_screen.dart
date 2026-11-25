import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_categories.dart';
import '../repositories/school_repository.dart';
import '../widgets/common.dart';
import '../widgets/design_system.dart';

const _modes = {
  'guardian_only': 'Somente família',
  'shared': 'Compartilhar com tutores autorizados',
  'paused': 'Acompanhamento escolar pausado',
};

Future<SchoolData> _observe(Future<SchoolData> pending) {
  // A fast failure can arrive before the rebuild subscribes FutureBuilder.
  // Observe immediately; the original future still delivers the error to UI.
  pending.ignore();
  return pending;
}

const _states = {
  'pending': 'Aguardando aceite',
  'active': 'Aceito',
  'declined': 'Recusado',
  'expired': 'Expirado',
  'revoked': 'Revogado',
};
String _scope(dynamic value) =>
    value == 'history' ? 'Categorias e horários' : 'Resumo por categoria';
String _date(dynamic seconds) {
  if (seconds is! num) return '';
  final date = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round())
      .toLocal();
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}

String _event(dynamic event) {
  const labels = {
    'invitation.created': 'Convite enviado',
    'invitation.active': 'Convite aceito',
    'invitation.declined': 'Convite recusado',
    'invitation.revoked': 'Acesso revogado',
    'privacy.shared': 'Compartilhamento ativado',
    'privacy.guardian_only': 'Acesso restrito à família',
    'privacy.paused': 'Acompanhamento escolar pausado',
    'activity.read': 'Tutor consultou a atividade',
  };
  return labels[event] ?? 'Preferência escolar atualizada';
}

/// Loading/errors replace cached content, so revoked information never remains
/// displayed while a permission refresh is failing.
class _SchoolBody extends StatelessWidget {
  const _SchoolBody({
    required this.future,
    required this.reload,
    required this.buildItems,
  });
  final Future<SchoolData>? future;
  final VoidCallback reload;
  final List<Widget> Function(SchoolData) buildItems;
  @override
  Widget build(BuildContext context) => ContentFrame(
    child: FutureBuilder<SchoolData>(
      future: future,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ListSkeleton();
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              EmptyState(
                message: snapshot.error.toString(),
                icon: Icons.cloud_off,
              ),
              OutlinedButton(
                onPressed: reload,
                child: const Text('Tentar novamente'),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: buildItems(snapshot.data!),
        );
      },
    ),
  );
}

class SchoolFamilyScreen extends StatefulWidget {
  const SchoolFamilyScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.readOnly = false,
  });
  final String childId, childName;
  final bool readOnly;
  @override
  State<SchoolFamilyScreen> createState() => _SchoolFamilyState();
}

class _SchoolFamilyState extends State<SchoolFamilyScreen> {
  Future<SchoolData>? future;
  bool busy = false;
  SchoolRepository get school => SchoolRepository(AppScope.of(context).api);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= _observe(school.family(widget.childId));
  }

  void reload() => setState(() {
    future = _observe(school.family(widget.childId));
  });
  Future<void> change(Future<void> Function() operation, String message) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      if (mounted) showFeedback(context, message);
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reload();
      }
    }
  }

  Future<void> invite(String version) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final candidates = await school.candidates();
      if (!mounted) return;
      final result = await showDialog<({String tutor, String scope})>(
        context: context,
        builder: (_) => _TutorInviteDialog(candidates: candidates),
      );
      if (result == null || !mounted) return;
      await school.invite(widget.childId, result.tutor, result.scope, version);
      if (mounted) {
        showFeedback(
          context,
          'Convite enviado. O tutor precisa aceitar e o compartilhamento precisa estar ativado.',
        );
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reload();
      }
    }
  }

  Future<void> revoke(SchoolData link) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Revogar acompanhamento?'),
        content: Text(
          '${link['name']} perderá o acesso escolar. Um novo acesso exigirá outro convite.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await change(
        () => school.revoke(widget.childId, link['id'] as String),
        'Acesso escolar revogado.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Acompanhamento escolar'),
      actions: [
        IconButton(
          tooltip: 'Atualizar acompanhamento',
          onPressed: busy ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _SchoolBody(
      future: future,
      reload: reload,
      buildItems: (data) => [
        Text(
          widget.childName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Tutores autorizados veem apenas categorias e, se permitido, horários de atividade. Mensagens, fotos, textos das publicações e histórico anterior à autorização não são compartilhados.',
        ),
        const SizedBox(height: 20),
        if (widget.readOnly) ...[
          Text(
            _modes[data['mode']] ?? 'Somente família',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Seu responsável gerencia essas permissões. Aqui você acompanha quem tem acesso.',
          ),
        ] else ...[
          for (final entry in _modes.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                data['mode'] == entry.key
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(entry.value),
              enabled: !busy,
              onTap: data['mode'] == entry.key || busy
                  ? null
                  : () => change(
                      () => school.privacy(widget.childId, entry.key),
                      'Preferência escolar atualizada.',
                    ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => invite(data['consentVersion'] as String),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(busy ? 'Aguarde…' : 'Convidar tutor'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Escolha um contato adulto aprovado que você conhece. O Conexia ainda não certifica vínculo profissional com a escola.',
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Tutores e convites',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if ((data['links'] as List).isEmpty)
          const EmptyState(
            message:
                'Nenhum tutor vinculado. O acesso continua restrito à família.',
            icon: Icons.school_outlined,
          ),
        for (final raw in data['links'] as List)
          Builder(
            builder: (_) {
              final link = raw as SchoolData;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link['name'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${_scope(link['scope'])} • ${_states[link['state']] ?? 'Encerrado'}',
                      ),
                      if (link['state'] == 'pending')
                        Text('Expira em ${_date(link['expires'])}'),
                      if (!widget.readOnly &&
                          ['pending', 'active'].contains(link['state']))
                        TextButton(
                          onPressed: busy ? null : () => revoke(link),
                          child: const Text('Revogar acesso'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 24),
        Text(
          'Transparência de acesso',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if ((data['audit'] as List).isEmpty)
          const Text('Nenhuma ação escolar registrada.'),
        for (final item in data['audit'] as List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(_event(item['event'])),
            subtitle: Text(_date(item['created'])),
          ),
      ],
    ),
  );
}

class _TutorInviteDialog extends StatefulWidget {
  const _TutorInviteDialog({required this.candidates});
  final List<SchoolData> candidates;
  @override
  State<_TutorInviteDialog> createState() => _TutorInviteState();
}

class _TutorInviteState extends State<_TutorInviteDialog> {
  String? tutor;
  String scope = 'summary';
  bool consent = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Convidar tutor'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.candidates.isEmpty)
              const Text(
                'Você ainda não tem contatos adultos disponíveis. Autorize primeiro o contato com o tutor que conhece.',
              )
            else ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Contato adulto aprovado',
                ),
                items: [
                  for (final candidate in widget.candidates)
                    DropdownMenuItem(
                      value: candidate['id'] as String,
                      child: Text(
                        candidate['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => tutor = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: scope,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Informações permitidas',
                ),
                items: [
                  for (final value in ['summary', 'history'])
                    DropdownMenuItem(value: value, child: Text(_scope(value))),
                ],
                onChanged: (value) => setState(() => scope = value!),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                title: const Text(
                  'Autorizo este acompanhamento escolar e entendo quais informações serão compartilhadas.',
                ),
                onChanged: (value) => setState(() => consent = value ?? false),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: tutor == null || !consent
            ? null
            : () => Navigator.pop(context, (tutor: tutor!, scope: scope)),
        child: const Text('Enviar convite'),
      ),
    ],
  );
}

class SchoolHubScreen extends StatefulWidget {
  const SchoolHubScreen({super.key});
  @override
  State<SchoolHubScreen> createState() => _SchoolHubState();
}

class _SchoolHubState extends State<SchoolHubScreen> {
  Future<SchoolData>? future;
  bool busy = false;
  SchoolRepository get school => SchoolRepository(AppScope.of(context).api);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= _observe(school.hub());
  }

  void reload() => setState(() {
    future = _observe(school.hub());
  });
  Future<void> decide(SchoolData invite, bool accept) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(accept ? 'Aceitar acompanhamento?' : 'Recusar convite?'),
        content: Text(
          accept
              ? 'Você poderá consultar ${_scope(invite['scope']).toLowerCase()} quando a família ativar o compartilhamento. Nenhuma mensagem privada ou foto será liberada.'
              : 'O convite será encerrado sem liberar acesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await school.decide(invite['id'] as String, accept);
      if (mounted) {
        showFeedback(
          context,
          accept
              ? 'Convite aceito. A família controla a liberação do acompanhamento.'
              : 'Convite recusado.',
        );
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Área do tutor'),
      actions: [
        IconButton(
          tooltip: 'Atualizar acompanhamento',
          onPressed: busy ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _SchoolBody(
      future: future,
      reload: reload,
      buildItems: (data) => [
        const Text(
          'O acompanhamento depende de convite, aceite e autorização ativa da família. Ser tutor não concede acesso administrativo.',
        ),
        const SizedBox(height: 24),
        Text(
          'Convites recebidos',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if ((data['items'] as List).isEmpty)
          const Text('Nenhum convite pendente.'),
        for (final invite in data['items'] as List)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Convite de ${invite['guardian']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(_scope(invite['scope'])),
                  Text('Expira em ${_date(invite['expires'])}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => decide(invite as SchoolData, true),
                        child: const Text('Aceitar'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => decide(invite as SchoolData, false),
                        child: const Text('Recusar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Alunos autorizados',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if ((data['students'] as List).isEmpty)
          const EmptyState(
            message: 'Nenhum acompanhamento liberado. Um convite aceito ainda depende da autorização ativa da família.',
            icon: Icons.school_outlined,
          ),
        for (final student in data['students'] as List)
          Card(
            child: ListTile(
              title: Text(student['name'] as String),
              subtitle: Text(_scope(student['scope'])),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SchoolActivityScreen(childId: student['id'] as String),
                  ),
                );
                if (mounted) reload();
              },
            ),
          ),
      ],
    ),
  );
}

class SchoolActivityScreen extends StatefulWidget {
  const SchoolActivityScreen({super.key, required this.childId});
  final String childId;
  @override
  State<SchoolActivityScreen> createState() => _SchoolActivityState();
}

class _SchoolActivityState extends State<SchoolActivityScreen>
    with WidgetsBindingObserver {
  Future<SchoolData>? future;
  int days = 7;
  Timer? permissionTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    permissionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        reload();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    permissionTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= _observe(fetch());
  }

  Future<SchoolData> fetch() =>
      SchoolRepository(AppScope.of(context).api).activity(widget.childId, days);
  void reload() => setState(() {
    future = _observe(fetch());
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Atividade escolar'),
      actions: [
        IconButton(
          tooltip: 'Atualizar acompanhamento',
          onPressed: reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _SchoolBody(
      future: future,
      reload: reload,
      buildItems: (data) => [
        Text(
          (data['child'] as SchoolData)['name'] as String,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(data['notice'] as String),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final value in [7, 30])
              ChoiceChip(
                label: Text('$value dias'),
                selected: days == value,
                onSelected: (_) {
                  setState(() => days = value);
                  reload();
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '${data['total']} registros no período',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if ((data['categories'] as List).isEmpty)
          const EmptyState(
            message: 'Ainda não há atividade no período autorizado.',
            icon: Icons.insights_outlined,
          ),
        for (final category in data['categories'] as List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(contentCategories[category['category']] ?? 'Outros'),
            trailing: Text(
              '${category['count']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        if (data['scope'] == 'history') ...[
          const SizedBox(height: 20),
          Text(
            'Registros recentes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final entry in data['history'] as List)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(contentCategories[entry['category']] ?? 'Outros'),
              subtitle: Text(_date(entry['seenAt'])),
            ),
        ],
      ],
    ),
  );
}
