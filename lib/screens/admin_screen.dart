import 'package:flutter/material.dart';

import '../widgets/common.dart';
import '../widgets/design_system.dart';
import 'enrollment_review_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Future<Map<String, dynamic>>? future;
  bool saving = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppScope.of(context).account?.isAdmin == true) {
      future ??= fetch();
    }
  }

  Future<Map<String, dynamic>> fetch() async {
    final api = AppScope.of(context).api;
    final version = api.sessionVersion;
    final summary = await api.request('GET', '/admin/summary');
    api.checkSession(version);
    final reports = await api.request('GET', '/admin/reports');
    return {'summary': summary, 'items': reports['items']};
  }

  void reload() => setState(() {
    future = fetch();
    future!.ignore();
  });

  Future<void> decide(Map<String, dynamic> report, String action) async {
    if (saving) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReportDecisionDialog(remove: action == 'remove'),
    );
    if (reason == null || !mounted || saving) return;
    setState(() => saving = true);
    try {
      await AppScope.of(context).api.request(
        'PATCH',
        '/admin/reports/${report['id']}',
        {'action': action, if (reason.isNotEmpty) 'reason': reason},
      );
      if (mounted) {
        AppScope.of(context).social.invalidate();
        showFeedback(context, 'Decisão registrada.');
        reload();
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Administração local'),
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: saving ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ContentFrame(
      child: AppScope.of(context).account?.isAdmin != true
          ? const EmptyState(message: 'Acesso restrito à administração.')
          : FutureBuilder<Map<String, dynamic>>(
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
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final summary =
                    snapshot.data!['summary'] as Map<String, dynamic>;
                final reports = (snapshot.data!['items'] as List)
                    .cast<Map<String, dynamic>>();
                const labels = {
                  'users': 'Contas',
                  'posts': 'Publicações',
                  'familyLinks': 'Vínculos familiares',
                  'pendingReports': 'Denúncias pendentes',
                  'suspendedUsers': 'Contas suspensas',
                  'unverifiedUsers': 'E-mails pendentes',
                  'reportedUsers': 'Autores denunciados',
                  'administrators': 'Administradores',
                  'connections': 'Conexões aprovadas',
                  'pendingConnections': 'Pedidos pendentes',
                  'messages': 'Mensagens',
                  'unreadMessages': 'Não lidas',
                  'comments': 'Comentários',
                  'likes': 'Curtidas',
                  'activeStories': 'Recortes ativos',
                  'expiredStories': 'Recortes expirados',
                  'feedViews': 'Exibições no feed',
                  'pendingMediaUploads': 'Fotos na fila de envio',
                  'pendingMediaDeletions': 'Arquivos a excluir',
                  'cloudMedia': 'Imagens no Storage',
                  'pendingMediaTransfers': 'Transferências em andamento',
                };
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Visão geral',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: labels.entries
                          .where((entry) => summary.containsKey(entry.key))
                          .map(
                            (entry) => SizedBox(
                              width: 145,
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${summary[entry.key] ?? 0}',
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(entry.value),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminEnrollmentScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Revisar cadastros de menores'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminUsersScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.people_outline),
                      label: const Text('Consultar contas e situações'),
                    ),
                    if (summary['mediaBytes'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Mídia armazenada: ${((summary['mediaBytes'] as num) / (1024 * 1024)).toStringAsFixed(1)} MB',
                        ),
                      ),
                    const Text(
                      'Denúncias recentes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Posts e comentários podem ser removidos. Denúncias sobre perfis ou conversas exigem investigação manual.',
                    ),
                    if (reports.isEmpty)
                      const EmptyState(message: 'Nenhuma denúncia registrada.'),
                    ...reports.map(
                      (report) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report['status'] == 'pending'
                                    ? 'Pendente'
                                    : report['status'] == 'removed'
                                    ? 'Conteúdo removido'
                                    : 'Arquivada',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (report['priority'] == 3)
                                const Text(
                                  'Prioridade alta • revisão humana',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              Text(report['reason'] as String),
                              if (report['content'] != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(report['content'] as String),
                                ),
                              if (report['status'] == 'pending')
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: saving
                                          ? null
                                          : () => decide(report, 'dismiss'),
                                      child: const Text('Arquivar'),
                                    ),
                                    if (report['targetType'] != 'other')
                                      OutlinedButton(
                                        onPressed: saving
                                            ? null
                                            : () => decide(report, 'remove'),
                                        child: const Text('Remover conteúdo'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    ),
  );
}

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsersScreen> {
  String status = 'all';
  String? cursor, error;
  bool loading = false, initialized = false;
  int generation = 0;
  List<Map<String, dynamic>> users = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      load();
    }
  }

  Future<void> load({bool append = false}) async {
    if (append && (loading || cursor == null)) return;
    final current = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (!append) users = [];
    });
    try {
      final query = Uri(
        queryParameters: {'status': status, if (append) 'cursor': cursor!},
      ).query;
      final result = await AppScope.of(context).api
          .request('GET', '/admin/users?$query');
      if (!mounted || current != generation) return;
      setState(() {
        users = [
          ...users,
          ...(result['items'] as List).cast<Map<String, dynamic>>(),
        ];
        cursor = result['nextCursor'] as String?;
      });
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  final changing = <String>{};
  Future<void> changeStatus(Map<String, dynamic> user) async {
    final id = user['id'] as String;
    if (changing.contains(id)) return;
    final suspend = user['status'] != 'suspended';
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _AccountStatusDialog(suspend: suspend),
    );
    if (!mounted || reason == null || changing.contains(id)) return;
    setState(() => changing.add(id));
    try {
      await AppScope.of(context).api.request(
        'PATCH',
        '/admin/users/${Uri.encodeComponent(id)}',
        {'status': suspend ? 'suspended' : 'active', 'reason': reason},
      );
      if (!mounted) return;
      await load();
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => changing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contas e situações')),
    body: ContentFrame(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Filtrar situação'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todas as contas')),
                DropdownMenuItem(
                  value: 'active',
                  child: Text('Ativas e verificadas'),
                ),
                DropdownMenuItem(value: 'suspended', child: Text('Suspensas')),
                DropdownMenuItem(
                  value: 'unverified',
                  child: Text('E-mail pendente'),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  status = v;
                  load();
                }
              },
            ),
          ),
          Expanded(
            child: loading && users.isEmpty
                ? const ListSkeleton()
                : ListView(
                    children: [
                      if (error != null) ...[
                        InlineNotice(message: error!, error: true),
                        TextButton(
                          onPressed: load,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                      ...users.map(
                        (u) => Card(
                          child: ListTile(
                            leading: Icon(
                              u['status'] == 'suspended'
                                  ? Icons.pause_circle_outline
                                  : Icons.person_outline,
                            ),
                            title: Text(u['name'] as String),
                            trailing: u['isAdmin'] == 1
                                ? null
                                : IconButton(
                                    tooltip: u['status'] == 'suspended'
                                        ? 'Reativar conta'
                                        : 'Suspender conta',
                                    onPressed: changing.contains(u['id'])
                                        ? null
                                        : () => changeStatus(u),
                                    icon: Icon(
                                      u['status'] == 'suspended'
                                          ? Icons.play_circle_outline
                                          : Icons.pause_circle_outline,
                                    ),
                                  ),
                            subtitle: Text(
                              '${u['email']}\n${u['status'] == 'suspended'
                                  ? 'Suspensa'
                                  : u['verified'] == 1
                                  ? 'Ativa e verificada'
                                  : 'E-mail pendente'}${u['isAdmin'] == 1 ? ' • Administrador' : ''}',
                            ),
                          ),
                        ),
                      ),
                      if (!loading && users.isEmpty && error == null)
                        const EmptyState(
                          message: 'Nenhuma conta nesse filtro.',
                        ),
                      if (cursor != null)
                        TextButton(
                          onPressed: loading ? null : () => load(append: true),
                          child: Text(
                            loading ? 'Carregando…' : 'Carregar mais contas',
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

class _AccountStatusDialog extends StatefulWidget {
  const _AccountStatusDialog({required this.suspend});
  final bool suspend;
  @override
  State<_AccountStatusDialog> createState() => _AccountStatusDialogState();
}

class _AccountStatusDialogState extends State<_AccountStatusDialog> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.suspend ? 'Suspender conta?' : 'Reativar conta?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'A decisão fica registrada no servidor. Informe o motivo da revisão.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: reason,
            maxLength: 300,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Motivo obrigatório'),
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
        onPressed: reason.text.trim().length < 3
            ? null
            : () => Navigator.pop(context, reason.text.trim()),
        child: const Text('Confirmar'),
      ),
    ],
  );
}

class _ReportDecisionDialog extends StatefulWidget {
  const _ReportDecisionDialog({required this.remove});
  final bool remove;
  @override
  State<_ReportDecisionDialog> createState() => _ReportDecisionDialogState();
}

class _ReportDecisionDialogState extends State<_ReportDecisionDialog> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.remove ? 'Remover conteúdo denunciado?' : 'Arquivar denúncia?',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.remove
                ? 'A publicação ou comentário será excluído. Essa ação não pode ser desfeita.'
                : 'A denúncia será encerrada sem excluir o conteúdo.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: reason,
            maxLength: 500,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Justificativa ao denunciante (opcional)',
              helperText: 'Sem nomes ou dados privados de outras pessoas.',
              helperMaxLines: 2,
            ),
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
        onPressed:
            reason.text.trim().isNotEmpty && reason.text.trim().length < 3
            ? null
            : () => Navigator.pop(context, reason.text.trim()),
        child: const Text('Confirmar'),
      ),
    ],
  );
}
