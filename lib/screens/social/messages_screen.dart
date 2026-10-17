import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../core/api_client.dart';
import '../../widgets/social/post_exposure.dart';
import '../denuncia_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: AppScope.of(context).social.revision,
    builder: (_, socialRevision, _) => Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Conversas disponíveis apenas entre contatos aprovados. Você pode desativar mensagens nas configurações.',
          ),
        ),
        Expanded(
          child: AsyncItems(
            key: ValueKey('$revision-$socialRevision'),
            load: () => AppScope.of(context).social.list('/contacts'),
            empty: 'Nenhum contato aprovado ainda.',
            builder: (_, row) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(row['name'] as String),
              subtitle: Text(
                row['approved'] == 1
                    ? 'Contato aprovado'
                    : 'Aguardando aprovação',
              ),
              onTap: row['approved'] != 1
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ChatScreen(
                            id: row['id'] as String,
                            name: row['name'] as String,
                          ),
                        ),
                      );
                      if (mounted) setState(() => revision++);
                    },
            ),
          ),
        ),
      ],
    ),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.id, required this.name});
  final String id, name;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final text = TextEditingController();
  final scroll = ScrollController();
  List<Map<String, dynamic>> messages = [];
  String? historyCursor;
  Timer? timer;
  String? error;
  bool sending = false, loading = false, initialized = false;
  bool firstLoaded = false, loadingOlder = false, reloadQueued = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      load();
      timer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (mounted &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            (ModalRoute.of(context)?.isCurrent ?? false)) {
          load();
        }
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load({bool older = false}) async {
    if (loading) {
      if (!older) reloadQueued = true;
      return;
    }
    if (older && historyCursor == null) return;
    setState(() {
      loading = true;
      loadingOlder = older;
    });
    final state = AppScope.of(context);
    final accountId = state.account?.id;
    final previousPixels = scroll.hasClients ? scroll.position.pixels : 0.0;
    final previousExtent = scroll.hasClients
        ? scroll.position.maxScrollExtent
        : 0.0;
    final followLatest =
        !firstLoaded ||
        (scroll.hasClients && previousExtent - previousPixels < 80);
    try {
      final query = older
          ? '?cursor=${Uri.encodeQueryComponent(historyCursor!)}'
          : '';
      final result = await state.api.request(
        'GET',
        '/messages/${widget.id}$query',
      );
      final items = (result['items'] as List).cast<Map<String, dynamic>>();
      if (mounted && state.account?.id == accountId) {
        setState(() {
          final merged = {
            for (final m in [...messages, ...items]) m['id'] as String: m,
          };
          messages = merged.values.toList()
            ..sort((a, b) {
              final byDate = (a['created'] as num).compareTo(
                b['created'] as num,
              );
              return byDate != 0
                  ? byDate
                  : (a['id'] as String).compareTo(b['id'] as String);
            });
          if (older || !firstLoaded) {
            historyCursor = result['nextCursor']?.toString();
          }
          firstLoaded = true;
          error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scroll.hasClients) return;
          if (older) {
            final target =
                previousPixels +
                scroll.position.maxScrollExtent -
                previousExtent;
            scroll.jumpTo(target.clamp(0.0, scroll.position.maxScrollExtent));
          } else if (followLatest) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          if (e is ApiException && (e.status == 403 || e.status == 404)) {
            messages = [];
            historyCursor = null;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          loadingOlder = false;
        });
        if (reloadQueued) {
          reloadQueued = false;
          unawaited(load());
        }
      }
    }
  }

  Future<void> markRead(String id) async {
    final state = AppScope.of(context);
    final accountId = state.account?.id;
    await state.api.request('POST', '/messages/${widget.id}/read', {
      'ids': [id],
    });
    if (mounted && state.account?.id == accountId) {
      setState(
        () => messages = messages
            .map((m) => m['id'] == id ? {...m, 'read': 1} : m)
            .toList(),
      );
    }
  }

  Future<void> send() async {
    if (sending || text.text.trim().isEmpty) return;
    final submitted = text.text;
    setState(() => sending = true);
    try {
      await AppScope.of(context).api
          .request('POST', '/messages/${widget.id}', {'text': submitted});
      if (!mounted) return;
      if (text.text == submitted) text.clear();
      await load();
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.name),
      actions: [
        IconButton(
          tooltip: 'Denunciar conversa',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => DenunciaScreen(target: widget.id),
            ),
          ),
          icon: const Icon(Icons.flag_outlined),
        ),
        IconButton(
          tooltip: 'Bloquear contato',
          onPressed: () async {
            try {
              await AppScope.of(context).api
                  .request('POST', '/blocks', {'target': widget.id});
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) showFeedback(context, e);
            }
          },
          icon: const Icon(Icons.block),
        ),
      ],
    ),
    body: ContentFrame(
      child: Column(
        children: [
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: !firstLoaded && loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                ? const EmptyState(
                    message: 'Comece com uma mensagem respeitosa.',
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length + 1,
                    itemBuilder: (_, index) {
                      if (index == 0) {
                        return historyCursor == null
                            ? const SizedBox.shrink()
                            : TextButton(
                                onPressed: loading
                                    ? null
                                    : () => load(older: true),
                                child: Text(
                                  loadingOlder
                                      ? 'Carregando…'
                                      : 'Carregar mensagens anteriores',
                                ),
                              );
                      }
                      final m = messages[index - 1];
                      final mine =
                          m['sender'] == AppScope.of(context).account?.id;
                      final bubble = Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Card(
                            color: mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m['text'] as String),
                                  if (mine)
                                    Text(
                                      m['read'] == 1 ? 'Lida' : 'Enviada',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      return !mine && m['read'] != 1
                          ? PostExposure(
                              key: ValueKey('message-${m['id']}'),
                              onDisplayed: () => markRead(m['id'] as String),
                              child: bubble,
                            )
                          : KeyedSubtree(
                              key: ValueKey('message-${m['id']}'),
                              child: bubble,
                            );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: text,
                      maxLength: 1000,
                      decoration: const InputDecoration(labelText: 'Mensagem'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Enviar mensagem',
                    onPressed: sending ? null : send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
