import 'package:flutter/material.dart';

class PainelResponsavelScreen extends StatefulWidget {
  const PainelResponsavelScreen({super.key});

  @override
  State<PainelResponsavelScreen> createState() => _PainelResponsavelScreenState();
}

class _PainelResponsavelScreenState extends State<PainelResponsavelScreen> {
  bool _filtroPorIdade = true;
  bool _aprovarContatos = true;
  bool _alertasDeRisco = true;

  void _mensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4A6CF7);
    return Scaffold(
      appBar: AppBar(title: const Text('Painel do responsável')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(backgroundColor: primary, child: Icon(Icons.child_care_rounded, color: Colors.white)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Perfil vinculado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      SizedBox(height: 3),
                      Text('@usuario  •  Perfil protegido'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('Proteções ativas', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Ajuste regras de segurança. Mudanças importantes devem ser explicadas de forma clara ao perfil vinculado.'),
          const SizedBox(height: 12),
          _ProtecaoTile(
            icon: Icons.filter_alt_outlined,
            title: 'Filtro por faixa etária',
            subtitle: 'Limita conteúdos inadequados para a idade cadastrada.',
            value: _filtroPorIdade,
            onChanged: (value) => setState(() => _filtroPorIdade = value),
          ),
          _ProtecaoTile(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Aprovar novos contatos',
            subtitle: 'Solicitações ficam pendentes antes de liberar interação.',
            value: _aprovarContatos,
            onChanged: (value) => setState(() => _aprovarContatos = value),
          ),
          _ProtecaoTile(
            icon: Icons.notifications_active_outlined,
            title: 'Alertas de segurança',
            subtitle: 'Avisa sobre denúncias, bloqueios e sinais de risco.',
            value: _alertasDeRisco,
            onChanged: (value) => setState(() => _alertasDeRisco = value),
          ),
          const SizedBox(height: 22),
          const Text('Acompanhamento seguro', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Indicador(icon: Icons.shield_outlined, value: '0', label: 'Alertas pendentes', color: const Color(0xFF237B68))),
              const SizedBox(width: 12),
              Expanded(child: _Indicador(icon: Icons.person_add_outlined, value: '0', label: 'Contatos aguardando', color: const Color(0xFF7A5AF8))),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              onTap: () => _mensagem('Quando houver alertas, eles aparecerão aqui com orientações de ação.'),
              leading: const Icon(Icons.campaign_outlined, color: primary),
              title: const Text('Central de alertas', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Denúncias e eventos de segurança, sem mostrar conversas privadas.'),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(18)),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.privacy_tip_outlined, color: primary),
                SizedBox(width: 12),
                Expanded(child: Text('Este painel não mostra mensagens privadas nem permite vigilância oculta. Ele existe para apoiar a proteção, a mediação e o diálogo familiar.')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtecaoTile extends StatelessWidget {
  const _ProtecaoTile({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: SwitchListTile(
          secondary: Icon(icon, color: const Color(0xFF4A6CF7)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle),
          value: value,
          activeColor: const Color(0xFF4A6CF7),
          onChanged: onChanged,
        ),
      );
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.black12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      );
}
