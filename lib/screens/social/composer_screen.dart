import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/common.dart';

class ComposerScreen extends StatefulWidget {
  const ComposerScreen({super.key, this.story = false, this.postId, this.initialText});
  final bool story;
  final String? postId, initialText;
  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}
class _ComposerScreenState extends State<ComposerScreen> {
  late final TextEditingController text;
  Uint8List? bytes;
  String? mime, error;
  bool busy = false;
  @override
  void initState() { super.initState(); text = TextEditingController(text: widget.initialText); }
  @override
  void dispose() { text.dispose(); super.dispose(); }
  Future<void> pick() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      final value = await file.readAsBytes();
      if (value.length > 5 * 1024 * 1024) { if (mounted) showFeedback(context, 'Escolha uma imagem de até 5 MB.'); return; }
      final type = value.length >= 8 && value[0] == 137 && value[1] == 80 ? 'image/png' : value.length >= 3 && value[0] == 255 && value[1] == 216 ? 'image/jpeg' : 'image/webp';
      if (mounted) setState(() { bytes = value; mime = type; });
    } catch (_) { if (mounted) showFeedback(context, 'Não foi possível abrir a galeria. Confira a permissão ou tente outro dispositivo.'); }
  }
  Future<void> publish() async {
    if (text.text.trim().isEmpty) { setState(() => error = 'Escreva uma legenda.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final api = AppScope.of(context).api;
      String? mid;
      if (bytes != null) mid = (await api.request('POST','/media', {'mime': mime, 'data': base64Encode(bytes!)}))['id'] as String;
      await api.request(widget.postId == null ? 'POST' : 'PATCH', widget.postId != null ? '/posts/${widget.postId}' : widget.story ? '/stories' : '/posts', {'text': text.text, if (mid != null) 'media': mid});
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.postId != null ? 'Editar publicação' : widget.story ? 'Novo story' : 'Criar publicação')), body: ContentFrame(child: ListView(padding: const EdgeInsets.all(24), children: [
    const Text('Compartilhe ideias, sem expor informações pessoais. Visível conforme a privacidade do seu perfil.'), const SizedBox(height: 20),
    TextField(controller: text, maxLength: 2000, minLines: 4, maxLines: 8, decoration: const InputDecoration(labelText: 'O que você quer compartilhar?')),
    if (bytes != null) ...[ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.memory(bytes!, height: 260, fit: BoxFit.contain)), TextButton(onPressed: busy ? null : () => setState(() => bytes = null), child: const Text('Remover imagem'))],
    if (widget.postId == null) OutlinedButton.icon(onPressed: busy ? null : pick, icon: const Icon(Icons.photo_outlined), label: const Text('Selecionar foto')),
    if (widget.story) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Este story expira em 24 horas. Vídeos aguardam integração de processamento e armazenamento.')),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 20), FilledButton(onPressed: busy ? null : publish, child: Text(busy ? 'Publicando…' : 'Publicar')),
  ])));
}
