import 'package:flutter/material.dart';
import '../../widgets/common.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();
  String submitted = '';
  int revision = 0;
  @override
  void dispose() { query.dispose(); super.dispose(); }
  Future<void> request(String target) async {
    try { await AppScope.of(context).api.request('POST','/contacts',{'target':target}); if (mounted) showFeedback(context,'Pedido de contato registrado.'); }
    catch (e) { if (mounted) showFeedback(context,e); }
  }
  @override
  Widget build(BuildContext context) => Column(children: [Padding(padding: const EdgeInsets.all(16), child: TextField(controller: query, maxLength: 60, decoration: InputDecoration(labelText: 'Pesquisar conexões', suffixIcon: IconButton(tooltip: 'Pesquisar', onPressed: () => setState(() { submitted = query.text; revision++; }), icon: const Icon(Icons.search))), onSubmitted: (v) => setState(() { submitted = v; revision++; }))), const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Perfis privados aparecem apenas para contatos aprovados. O diretório não expõe menores desconhecidos.')), const SizedBox(height: 16), Expanded(child: AsyncItems(key: ValueKey(revision), load: () => AppScope.of(context).social.list('/profiles?q=${Uri.encodeQueryComponent(submitted)}'), empty: 'Nenhum perfil disponível pelas regras de privacidade.', builder: (_,row) => ListTile(leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(row['name'] as String), subtitle: Text(row['bio'] as String), trailing: IconButton(tooltip: 'Solicitar contato', onPressed: () => request(row['id'] as String), icon: const Icon(Icons.person_add_outlined))))) ]);
}
