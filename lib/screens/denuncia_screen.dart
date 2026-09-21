import 'package:flutter/material.dart';

class DenunciaScreen extends StatefulWidget {
  const DenunciaScreen({super.key});

  @override
  State<DenunciaScreen> createState() => _DenunciaScreenState();
}

class _DenunciaScreenState extends State<DenunciaScreen> {
  String? _motivo;

  final _motivos = const [
    'Bullying, ofensa ou humilhação',
    'Conteúdo que me deixou desconfortável',
    'Pessoa desconhecida tentando contato',
    'Informação pessoal exposta',
    'Outro motivo',
  ];

  void _enviarDenuncia() {
    if (_motivo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escolha um motivo para continuar.')));
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.verified_outlined, color: Color(0xFF237B68), size: 42),
        title: const Text('Denúncia enviada'),
        content: const Text('Obrigado por avisar. A equipe de moderação vai analisar a situação. Se você se sentir em risco, procure uma pessoa adulta de confiança agora.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/inicio', (route) => false),
            child: const Text('Voltar ao início'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Denunciar')), 
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.flag_outlined, size: 52, color: Color(0xFF4A6CF7)),
              const SizedBox(height: 16),
              const Text('Conte o que aconteceu', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Sua denúncia será vista apenas pela equipe de proteção. Escolha o motivo que melhor descreve a situação.'),
              const SizedBox(height: 22),
              ..._motivos.map(
                (motivo) => Card(
                  child: RadioListTile<String>(
                    value: motivo,
                    groupValue: _motivo,
                    onChanged: (value) => setState(() => _motivo = value),
                    title: Text(motivo),
                    activeColor: const Color(0xFF4A6CF7),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(16)),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF4A6CF7)),
                    SizedBox(width: 10),
                    Expanded(child: Text('Você também pode bloquear o perfil. Isso impede novas interações enquanto a denúncia é analisada.', style: TextStyle(fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(onPressed: _enviarDenuncia, child: const Text('Enviar denúncia')),
              ),
            ],
          ),
        ),
      );
}
