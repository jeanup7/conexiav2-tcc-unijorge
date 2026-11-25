import 'package:flutter/material.dart';

import '../widgets/common.dart';

class DenunciaScreen extends StatefulWidget {
  const DenunciaScreen({super.key, this.target});
  final String? target;
  @override
  State<DenunciaScreen> createState() => _DenunciaScreenState();
}

class _DenunciaScreenState extends State<DenunciaScreen> {
  String? reason;
  final details = TextEditingController();
  bool busy = false, notifyGuardian = false;
  static const reasons = {
    'Bullying ou ofensa': 'bullying',
    'Contato indesejado': 'unwanted_contact',
    'Exposição de informação pessoal': 'personal_information',
    'Conteúdo inadequado': 'inappropriate_content',
    'Discurso de ódio': 'hate',
    'Ameaça ou violência': 'threat',
    'Risco ou exploração de menores': 'child_safety',
    'Golpe ou fraude': 'scam',
    'Outro motivo': 'other',
  };
  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy) return;
    if (reason == null) {
      showFeedback(context, 'Escolha um motivo.');
      return;
    }
    setState(() => busy = true);
    try {
      final result = await AppScope.of(context).api
          .request('POST', '/reports', {
            'target': widget.target ?? 'general',
            'reason': '$reason ${details.text}',
            'category': reasons[reason],
            'notifyGuardian': notifyGuardian,
          });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Denúncia registrada'),
          content: Text(
            'Protocolo: ${result['id']}\nA fila foi registrada no servidor. A equipe de atendimento ainda precisa ser configurada. Se houver risco, procure um adulto de confiança.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pedir ajuda • denúncia')),
    body: ContentFrame(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Conte o que aconteceu',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'Não inclua dados pessoais desnecessários. Sua denúncia fica vinculada ao conteúdo ou perfil selecionado.',
          ),
          const SizedBox(height: 24),
          ...reasons.keys.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoiceChip(
                label: Text(v),
                selected: reason == v,
                onSelected: busy ? null : (_) => setState(() => reason = v),
              ),
            ),
          ),
          if (AppScope.of(context).account?.needsGuardian == true)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pedir apoio ao meu responsável'),
              subtitle: const Text(
                'Envia apenas um aviso de apoio. O texto da denúncia e suas mensagens não são enviados.',
              ),
              value: notifyGuardian,
              onChanged: busy
                  ? null
                  : (value) => setState(() => notifyGuardian = value ?? false),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: details,
            maxLength: 500,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Detalhes opcionais'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : send,
            child: Text(busy ? 'Enviando…' : 'Registrar denúncia'),
          ),
        ],
      ),
    ),
  );
}
