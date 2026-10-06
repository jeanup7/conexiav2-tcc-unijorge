import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/common.dart';
import '../denuncia_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}
class _MessagesScreenState extends State<MessagesScreen> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => Column(children: [const Padding(padding: EdgeInsets.all(16), child: Text('Conversas disponíveis apenas entre contatos aprovados. Você pode desativar mensagens nas configurações.')), Expanded(child: AsyncItems(key: ValueKey(revision), load: () => AppScope.of(context).social.list('/contacts'), empty: 'Nenhum contato aprovado ainda.', builder: (_,row) => ListTile(leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(row['name'] as String), subtitle: Text(row['approved'] == 1 ? 'Contato aprovado' : 'Aguardando aprovação'), onTap: row['approved'] != 1 ? null : () async { await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChatScreen(id: row['id'] as String, name: row['name'] as String))); if (mounted) setState(() => revision++); }))) ]);
}
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.id, required this.name});
  final String id,name;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final text = TextEditingController();
  List<Map<String,dynamic>> messages = [];
  Timer? timer;
  String? error;
  bool sending = false, loading = false, initialized = false;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); if (!initialized) { initialized = true; load(); timer = Timer.periodic(const Duration(seconds: 8), (_) { if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) load(); }); } }
  @override
  void dispose() { timer?.cancel(); text.dispose(); super.dispose(); }
  Future<void> load() async {
    if (loading) return;
    loading = true;
    try { final items = await AppScope.of(context).social.list('/messages/${widget.id}'); if (mounted) setState(() { messages = items; error = null; }); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { loading = false; }
  }
  Future<void> send() async {
    setState(() => sending = true);
    try { await AppScope.of(context).api.request('POST','/messages/${widget.id}',{'text':text.text}); text.clear(); if (mounted) await load(); }
    catch (e) { if (mounted) showFeedback(context,e); }
    finally { if (mounted) setState(() => sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.name), actions: [IconButton(tooltip: 'Denunciar conversa', onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => DenunciaScreen(target: widget.id))), icon: const Icon(Icons.flag_outlined)), IconButton(tooltip: 'Bloquear contato', onPressed: () async { try { await AppScope.of(context).api.request('POST','/blocks',{'target':widget.id}); if (context.mounted) Navigator.pop(context); } catch(e) { if (context.mounted) showFeedback(context,e); } }, icon: const Icon(Icons.block))]), body: ContentFrame(child: Column(children: [
    if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
    Expanded(child: messages.isEmpty ? const EmptyState(message: 'Comece com uma mensagem respeitosa.') : ListView(padding: const EdgeInsets.all(16), children: messages.map((m) { final mine = m['sender'] == AppScope.of(context).account?.id; return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: Card(color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.white, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['text'] as String), if (mine) Text(m['read'] == 1 ? 'Lida' : 'Enviada', style: Theme.of(context).textTheme.labelSmall)]))))); }).toList())),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: TextField(controller: text, maxLength: 1000, decoration: const InputDecoration(labelText: 'Mensagem'))), IconButton(tooltip: 'Enviar mensagem', onPressed: sending ? null : send, icon: const Icon(Icons.send))]))),
  ])));
}
