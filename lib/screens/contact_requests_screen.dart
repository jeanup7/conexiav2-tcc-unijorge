import 'package:flutter/material.dart';

import '../widgets/common.dart';

class ContactRequestsScreen extends StatefulWidget {
  const ContactRequestsScreen({super.key, this.childId, this.childName});
  final String? childId, childName;
  @override
  State<ContactRequestsScreen> createState() => _ContactRequestsState();
}

class _ContactRequestsState extends State<ContactRequestsScreen> {
  int revision = 0;
  final pending = <String>{};
  bool get guardian => widget.childId != null;
  String get endpoint => guardian
      ? '/guardian/children/${widget.childId}/contacts'
      : '/contacts/requests';

  Future<void> decide(Map<String, dynamic> row, bool approve) async {
    final id = (guardian ? row['id'] : row['requestId']) as String;
    if (!pending.add(id)) return;
    setState(() {});
    final state = AppScope.of(context);
    try {
      final result = guardian
          ? await state.api.request('PATCH', '$endpoint/$id', {
              'approved': approve,
            })
          : approve
          ? await state.api.request('POST', '/contacts/approve', {
              'target': row['id'],
            })
          : await state.api.request('DELETE', '/contacts/requests/$id');
      if (!mounted) return;
      state.social.invalidate();
      setState(() => revision++);
      showFeedback(
        context,
        !approve
            ? 'Conexão recusada ou removida.'
            : result['status'] == 'approved'
            ? 'Conexão liberada.'
            : 'Decisão registrada. A conexão aguarda as outras autorizações.',
      );
    } catch (error) {
      if (mounted) showFeedback(context, error);
    } finally {
      pending.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        guardian
            ? 'Contatos de ${widget.childName ?? 'perfil vinculado'}'
            : 'Pedidos de contato',
      ),
      actions: [
        IconButton(
          tooltip: 'Atualizar pedidos',
          onPressed: () => setState(() => revision++),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ContentFrame(
      child: AsyncItems(
        key: ValueKey(revision),
        load: () => AppScope.of(context).social.list(endpoint),
        empty: guardian
            ? 'Nenhum pedido ou contato para analisar.'
            : 'Nenhum pedido pendente.',
        builder: (_, row) {
          final id = (guardian ? row['id'] : row['requestId']) as String;
          final disabled = pending.contains(id);
          final connected = row['status'] == 'approved';
          final accepted = row['accepted'] == true;
          final authorized = row['approved'] == true;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['name'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    row['incoming'] == true
                        ? 'Pedido recebido'
                        : 'Pedido enviado',
                  ),
                  if (guardian)
                    const Text(
                      'Autorize somente pessoas que você e o menor conhecem.',
                    ),
                  if (connected)
                    const Text(
                      'Conexão ativa. Você pode retirar a autorização.',
                    ),
                  if (!connected && accepted)
                    const Text(
                      'Aceito pelo destinatário; aguardando autorizações familiares.',
                    ),
                  if (!guardian && row['requiresGuardian'] == true)
                    const Text(
                      'A conexão depende da autorização de cada responsável envolvido.',
                    ),
                  if (guardian && authorized && !connected)
                    const Text('Sua autorização já foi registrada.'),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (guardian
                          ? !connected && !authorized
                          : row['incoming'] == true && !accepted)
                        FilledButton(
                          onPressed: disabled ? null : () => decide(row, true),
                          child: Text(
                            guardian ? 'Autorizar' : 'Aceitar pedido',
                          ),
                        ),
                      TextButton(
                        onPressed: disabled ? null : () => decide(row, false),
                        child: Text(
                          connected
                              ? 'Retirar autorização'
                              : 'Recusar ou cancelar',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
