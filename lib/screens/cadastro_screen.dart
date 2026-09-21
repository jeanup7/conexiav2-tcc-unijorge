import 'package:flutter/material.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _responsavel = false;
  bool _vincularResponsavel = true;

  final TextEditingController nascimentoController =
      TextEditingController();
  final TextEditingController responsavelNomeController =
      TextEditingController();
  final TextEditingController responsavelEmailController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    responsavelNomeController.addListener(_atualizarFormulario);
    responsavelEmailController.addListener(_atualizarFormulario);
  }

  void _atualizarFormulario() => setState(() {});

  @override
  void dispose() {
    nascimentoController.dispose();
    responsavelNomeController.removeListener(_atualizarFormulario);
    responsavelEmailController.removeListener(_atualizarFormulario);
    responsavelNomeController.dispose();
    responsavelEmailController.dispose();
    super.dispose();
  }

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
              horizontal: 25,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // VOLTAR
                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                  ),
                ),

                const SizedBox(height: 10),

                // ÍCONE
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
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
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // TÍTULO
                const Center(
                  child: Text(
                    'Criar sua conta',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                const Center(
                  child: Text(
                    'Vamos criar seu espaço de forma segura.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 15,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Perfil da criança ou adolescente',
                  style: TextStyle(
                    color: Color(0xFF4A6CF7),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 8),

                // NOME
                const Text(
                  'Como podemos chamar você?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  decoration: campoEstilo(
                    'Nome ou apelido',
                    Icons.person_outline_rounded,
                  ),
                ),

                const SizedBox(height: 18),

                // USUÁRIO
                const Text(
                  'Escolha seu nome de usuário',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  decoration: campoEstilo(
                    '@usuario',
                    Icons.alternate_email_rounded,
                  ),
                ),

                const SizedBox(height: 18),

                // DATA DE NASCIMENTO
                const Text(
                  'Data de nascimento',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: nascimentoController,
                  readOnly: true,
                  decoration: campoEstilo(
                    'DD/MM/AAAA',
                    Icons.calendar_month_outlined,
                  ),
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      initialDate: DateTime(2012),
                    );

                    if (data != null) {
                      nascimentoController.text =
                          '${data.day.toString().padLeft(2, '0')}/'
                          '${data.month.toString().padLeft(2, '0')}/'
                          '${data.year}';
                    }
                  },
                ),

                const SizedBox(height: 12),

                // AVISO SOBRE IDADE
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF4A6CF7),
                      ),

                      SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          'Sua idade será utilizada para aplicar '
                          'recursos de proteção e segurança adequados '
                          'à sua faixa etária.',
                          style: TextStyle(
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // SENHA
                const Text(
                  'Crie uma senha',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  obscureText: _obscurePassword,
                  decoration: campoEstilo(
                    'Senha',
                    Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword =
                              !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // CONFIRMAR SENHA
                TextField(
                  obscureText: _obscureConfirmPassword,
                  decoration: campoEstilo(
                    'Confirme sua senha',
                    Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword =
                              !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                // CONTA EM FAMÍLIA
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.black12,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.family_restroom_rounded,
                            color: Color(0xFF4A6CF7),
                            size: 28,
                          ),

                          SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              'Conta em família',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        'Crie um perfil de responsável vinculado. '
                        'Ele ajuda a configurar proteções adequadas '
                        'para a idade e a acompanhar alertas de segurança.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),

                      const SizedBox(height: 10),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _vincularResponsavel,
                        onChanged: (value) {
                          setState(() {
                            _vincularResponsavel = value;
                          });
                        },
                        activeColor: const Color(0xFF4A6CF7),
                        title: const Text(
                          'Vincular um responsável agora',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'O vínculo também poderá ser concluído depois.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),

                      if (_vincularResponsavel) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: responsavelNomeController,
                          textCapitalization: TextCapitalization.words,
                          decoration: campoEstilo(
                            'Nome do responsável',
                            Icons.person_outline_rounded,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: responsavelEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: campoEstilo(
                            'E-mail do responsável',
                            Icons.email_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF0FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.privacy_tip_outlined,
                                color: Color(0xFF4A6CF7),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'O responsável poderá definir filtros por idade, '
                                  'aprovar contatos e receber alertas de risco. '
                                  'Mensagens privadas não são compartilhadas por padrão.',
                                  style: TextStyle(fontSize: 12, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _responsavel,
                        onChanged: (value) {
                          setState(() {
                            _responsavel = value ?? false;
                          });
                        },
                        title: const Text(
                          'Estou ciente dessas condições.',
                          style: TextStyle(
                            fontSize: 14,
                          ),
                        ),
                        controlAffinity:
                            ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // TERMOS
                const Text(
                  'Ao continuar, você declara que as '
                  'informações fornecidas são verdadeiras '
                  'e concorda em utilizar a plataforma '
                  'respeitando as regras de segurança.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),

                const SizedBox(height: 22),

                // BOTÃO
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _responsavel &&
                            (!_vincularResponsavel ||
                                (responsavelNomeController.text.trim().isNotEmpty &&
                                    responsavelEmailController.text.trim().isNotEmpty))
                        ? () {
                            // Vai para a tela de segurança
                            Navigator.pushNamed(
                              context,
                              '/seguranca',
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF4A6CF7),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Continuar cadastro',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                // PRIVACIDADE
                const Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
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

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================
// ESTILO DOS CAMPOS
// ======================================================

InputDecoration campoEstilo(
  String label,
  IconData icon, {
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,

    contentPadding: const EdgeInsets.symmetric(
      vertical: 18,
      horizontal: 16,
    ),

    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),

    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),

    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(
        color: Color(0xFF4A6CF7),
        width: 2,
      ),
    ),
  );
}
