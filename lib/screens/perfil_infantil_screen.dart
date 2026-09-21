import 'package:flutter/material.dart';

class PerfilInfantilScreen extends StatelessWidget {
  const PerfilInfantilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4A6CF7);
    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 46,
              backgroundColor: Color(0xFFEAF0FF),
              child: Icon(Icons.person_rounded, size: 54, color: primary),
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: Text('Meu espaço', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
          const SizedBox(height: 4),
          const Center(child: Text('@usuario  •  Perfil privado')),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(18)),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: primary),
                SizedBox(width: 12),
                Expanded(child: Text('Seu perfil está protegido. Você decide o que publicar e pode denunciar ou bloquear qualquer pessoa.')),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('Minhas escolhas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const _PerfilOpcao(icon: Icons.privacy_tip_outlined, title: 'Privacidade', subtitle: 'Perfil privado e contatos aprovados'),
          const _PerfilOpcao(icon: Icons.block_outlined, title: 'Pessoas bloqueadas', subtitle: 'Gerencie quem não pode interagir com você'),
          const _PerfilOpcao(icon: Icons.flag_outlined, title: 'Minhas denúncias', subtitle: 'Veja atualizações sobre pedidos de ajuda'),
          const SizedBox(height: 22),
          const Text('Conta em família', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Esta conta possui um responsável vinculado para configurar proteções e receber alertas de segurança.'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/painel-responsavel'),
            icon: const Icon(Icons.family_restroom_outlined),
            label: const Text('Demonstração do painel responsável'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No aplicativo final, esse acesso exige autenticação exclusiva do responsável.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ],
      ),
    );
  }
}

class _PerfilOpcao extends StatelessWidget {
  const _PerfilOpcao({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF4A6CF7)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
