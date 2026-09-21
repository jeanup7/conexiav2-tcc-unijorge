import 'package:flutter/material.dart';

class SegurancaScreen extends StatefulWidget {
  const SegurancaScreen({super.key});

  @override
  State<SegurancaScreen> createState() => _SegurancaScreenState();
}

class _SegurancaScreenState extends State<SegurancaScreen> {
  bool notificacoesSeguranca = true;
  bool filtroConteudo = true;
  bool mensagensDesconhecidos = true;
  bool perfilPrivado = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEAF0FF),
              Color(0xFFF8FAFF),
              Color(0xFFE8F8F5),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ÍCONE
                Center(
                  child: Container(
                    width: 95,
                    height: 95,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF4A6CF7),
                          Color(0xFF55C9B0),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.security_rounded,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // TÍTULO
                const Center(
                  child: Text(
                    'Sua segurança',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                const Center(
                  child: Text(
                    'Vamos deixar seu espaço mais seguro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // AVISO
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.black12,
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF4A6CF7),
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Algumas configurações de segurança '
                          'serão ativadas para ajudar a proteger '
                          'sua experiência na plataforma.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                const Text(
                  'Configurações de proteção',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                // PERFIL PRIVADO
                _configuracao(
                  titulo: 'Perfil privado',
                  descricao:
                      'Seu perfil fica visível apenas para pessoas '
                      'que você permitir.',
                  icone: Icons.lock_outline_rounded,
                  valor: perfilPrivado,
                  aoAlterar: (valor) {
                    setState(() {
                      perfilPrivado = valor;
                    });
                  },
                ),

                // FILTRO DE CONTEÚDO
                _configuracao(
                  titulo: 'Filtro de conteúdo',
                  descricao:
                      'Ajuda a limitar conteúdos inadequados '
                      'para sua faixa etária.',
                  icone: Icons.filter_alt_outlined,
                  valor: filtroConteudo,
                  aoAlterar: (valor) {
                    setState(() {
                      filtroConteudo = valor;
                    });
                  },
                ),

                // MENSAGENS
                _configuracao(
                  titulo: 'Mensagens de desconhecidos',
                  descricao:
                      'Impede que pessoas desconhecidas enviem '
                      'mensagens diretamente para você.',
                  icone: Icons.message_outlined,
                  valor: mensagensDesconhecidos,
                  aoAlterar: (valor) {
                    setState(() {
                      mensagensDesconhecidos = valor;
                    });
                  },
                ),

                // NOTIFICAÇÕES
                _configuracao(
                  titulo: 'Alertas de segurança',
                  descricao:
                      'Receba avisos quando houver alguma '
                      'atividade importante relacionada à segurança.',
                  icone: Icons.notifications_none_rounded,
                  valor: notificacoesSeguranca,
                  aoAlterar: (valor) {
                    setState(() {
                      notificacoesSeguranca = valor;
                    });
                  },
                ),

                const SizedBox(height: 20),

                // INFORMAÇÃO
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF4A6CF7),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'As configurações de proteção podem '
                          'variar de acordo com a idade informada '
                          'no cadastro.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // BOTÃO CONTINUAR
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/inicio');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF4A6CF7),
                      foregroundColor: Colors.white,
                      elevation: 5,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Continuar',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // RODAPÉ
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: Colors.grey,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Sua segurança é nossa prioridade',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ======================================================
  // WIDGET DE CONFIGURAÇÃO
  // ======================================================

  Widget _configuracao({
    required String titulo,
    required String descricao,
    required IconData icone,
    required bool valor,
    required Function(bool) aoAlterar,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black12,
        ),
      ),
      child: SwitchListTile(
        value: valor,
        onChanged: aoAlterar,
        activeColor: const Color(0xFF4A6CF7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        secondary: Icon(
          icone,
          color: const Color(0xFF4A6CF7),
          size: 28,
        ),
        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            descricao,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}
