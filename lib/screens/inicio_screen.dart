import 'package:flutter/material.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  int _selectedIndex = 0;
  String? _humor;

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  void _abrirAjuda() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pedir ajuda', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Se algo deixou você desconfortável, você não precisa lidar com isso sozinho. Conte para uma pessoa adulta de confiança ou use a denúncia no aplicativo.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _mostrarMensagem('Você poderá escolher uma pessoa de confiança na próxima etapa.');
              },
              icon: const Icon(Icons.people_outline),
              label: const Text('Falar com pessoa de confiança'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4A6CF7);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFF),
        surfaceTintColor: Colors.transparent,
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: primary),
            SizedBox(width: 8),
            Text('Conexão Segura', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Configurações de proteção',
            onPressed: () => Navigator.pushNamed(context, '/seguranca'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const Text('Olá! Que bom ter você aqui.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Este é um espaço para criar, aprender e se conectar com respeito.'),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF4A6CF7), Color(0xFF55C9B0)]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, color: Colors.white, size: 32),
                  SizedBox(height: 10),
                  Text('Você está no controle', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text('Protegemos sua privacidade e explicamos as ferramentas de segurança de um jeito claro.', style: TextStyle(color: Colors.white, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Como você está hoje?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Escolher um sentimento é opcional e fica só nesta tela.'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HumorChip(emoji: '😊', label: 'Bem', selected: _humor == 'Bem', onTap: () => setState(() => _humor = 'Bem')),
                _HumorChip(emoji: '😐', label: 'Mais ou menos', selected: _humor == 'Mais ou menos', onTap: () => setState(() => _humor = 'Mais ou menos')),
                _HumorChip(emoji: '😟', label: 'Preciso falar', selected: _humor == 'Preciso falar', onTap: () => setState(() => _humor = 'Preciso falar')),
              ],
            ),
            const SizedBox(height: 26),
            const Text('Ferramentas para você', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _AcaoCard(icon: Icons.flag_outlined, title: 'Denunciar', subtitle: 'Sinalize algo errado', color: const Color(0xFFE85959), onTap: () => _mostrarMensagem('A denúncia será enviada para avaliação da moderação.'))),
                const SizedBox(width: 12),
                Expanded(child: _AcaoCard(icon: Icons.block_outlined, title: 'Bloquear', subtitle: 'Afaste contatos', color: const Color(0xFF7A5AF8), onTap: () => _mostrarMensagem('Você poderá bloquear um perfil ao abrir uma conversa ou publicação.'))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _AcaoCard(icon: Icons.privacy_tip_outlined, title: 'Privacidade', subtitle: 'Veja quem pode ver', color: const Color(0xFF237B68), onTap: () => Navigator.pushNamed(context, '/seguranca'))),
                const SizedBox(width: 12),
                Expanded(child: _AcaoCard(icon: Icons.volunteer_activism_outlined, title: 'Pedir ajuda', subtitle: 'Você não está só', color: const Color(0xFFE98B2A), onTap: _abrirAjuda)),
              ],
            ),
            const SizedBox(height: 26),
            const Text('Feed protegido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('Publicações de espaços moderados. Seja gentil e respeite as escolhas de cada pessoa.'),
            const SizedBox(height: 12),
            _PostProtegido(
              comunidade: 'Clube de histórias',
              autor: 'Lia',
              horario: 'há 12 min',
              conteudo: 'Terminei uma história sobre uma cidade nas nuvens! Qual nome vocês dariam para a cidade?',
              tema: 'Criatividade',
              onDenunciar: () => Navigator.pushNamed(context, '/denuncia'),
              onBloquear: () => _confirmarBloqueio('Lia'),
              onReagir: () => _mostrarMensagem('Reação enviada com respeito!'),
            ),
            _PostProtegido(
              comunidade: 'Oficina de ideias',
              autor: 'Rafa',
              horario: 'há 35 min',
              conteudo: 'Meu desafio de hoje: criar algo novo usando papel, lápis e muita imaginação. Topam tentar?',
              tema: 'Aprendizado',
              onDenunciar: () => Navigator.pushNamed(context, '/denuncia'),
              onBloquear: () => _confirmarBloqueio('Rafa'),
              onReagir: () => _mostrarMensagem('Reação enviada com respeito!'),
            ),
            const SizedBox(height: 18),
            const Text('Espaços para explorar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _EspacoCard(icon: Icons.auto_stories_outlined, title: 'Clube de histórias', subtitle: 'Leia, crie e compartilhe ideias com respeito.', onTap: () => _mostrarMensagem('O Clube de histórias estará disponível em breve.')),
            _EspacoCard(icon: Icons.lightbulb_outline, title: 'Oficina de ideias', subtitle: 'Desafios criativos e atividades para aprender.', onTap: () => _mostrarMensagem('A Oficina de ideias estará disponível em breve.')),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          if (index == 2) Navigator.pushNamed(context, '/seguranca');
          if (index == 3) Navigator.pushNamed(context, '/perfil-infantil');
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explorar'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Proteção'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }

  Future<void> _confirmarBloqueio(String nome) async {
    final bloquear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bloquear perfil?'),
        content: Text('Você deixará de ver as publicações de $nome e essa pessoa não poderá interagir com você.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bloquear')),
        ],
      ),
    );
    if (bloquear == true && mounted) {
      _mostrarMensagem('Perfil bloqueado. Você pode mudar isso nas configurações.');
    }
  }
}

class _HumorChip extends StatelessWidget {
  const _HumorChip({required this.emoji, required this.label, required this.selected, required this.onTap});

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        label: Text('$emoji  $label'),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      );
}

class _AcaoCard extends StatelessWidget {
  const _AcaoCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: 0.25))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 29),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
      );
}

class _EspacoCard extends StatelessWidget {
  const _EspacoCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(backgroundColor: const Color(0xFFEAF0FF), child: Icon(icon, color: const Color(0xFF4A6CF7))),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}

class _PostProtegido extends StatelessWidget {
  const _PostProtegido({
    required this.comunidade,
    required this.autor,
    required this.horario,
    required this.conteudo,
    required this.tema,
    required this.onDenunciar,
    required this.onBloquear,
    required this.onReagir,
  });

  final String comunidade;
  final String autor;
  final String horario;
  final String conteudo;
  final String tema;
  final VoidCallback onDenunciar;
  final VoidCallback onBloquear;
  final VoidCallback onReagir;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFEAF0FF),
                    child: Text(autor.substring(0, 1), style: const TextStyle(color: Color(0xFF4A6CF7), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(autor, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('$comunidade  •  $horario', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opções da publicação',
                    onSelected: (value) {
                      if (value == 'denunciar') onDenunciar();
                      if (value == 'bloquear') onBloquear();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'denunciar', child: Text('Denunciar publicação')),
                      PopupMenuItem(value: 'bloquear', child: Text('Bloquear perfil')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(conteudo, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFE8F8F5), borderRadius: BorderRadius.circular(20)),
                child: Text('Espaço seguro • $tema', style: const TextStyle(fontSize: 12, color: Color(0xFF237B68), fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(onPressed: onReagir, icon: const Icon(Icons.favorite_border), label: const Text('Gostei')),
                  TextButton.icon(onPressed: onDenunciar, icon: const Icon(Icons.flag_outlined), label: const Text('Denunciar')),
                ],
              ),
            ],
          ),
        ),
      );
}
