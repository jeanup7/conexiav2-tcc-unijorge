import '../widgets/design_system.dart';

import 'package:flutter/material.dart';

import '../widgets/common.dart';

class ChildAccountScreen extends StatefulWidget {
  const ChildAccountScreen({super.key});
  @override
  State<ChildAccountScreen> createState() => _ChildAccountState();
}

class _ChildAccountState extends State<ChildAccountScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  DateTime? birth;
  bool busy = false, consent = false;
  String? error;
  @override
  void dispose() {
    for (final c in [name, email, password, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!form.currentState!.validate() || birth == null || !consent) {
      setState(
        () => error = 'Revise os campos, a data de nascimento e a autorização.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sent = await AppScope.of(context).createChild({
        'name': name.text.trim(),
        'email': email.text.trim(),
        'password': password.text,
        'birth': birth!.toIso8601String().split('T').first,
      });
      if (!mounted) return;
      showFeedback(
        context,
        sent
            ? 'Perfil vinculado. O e-mail de confirmação foi enviado ao menor.'
            : 'Perfil vinculado, mas o envio falhou. O menor pode entrar e reenviar a confirmação.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Perfil do menor')),
    body: ContentFrame(
      width: 520,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Você continuará na sua conta. O menor entrará com o próprio e-mail e escolherá o apelido exibido no feed.',
          ),
          const SizedBox(height: 20),
          Form(
            key: form,
            child: Column(
              children: [
                TextFormField(
                  enabled: !busy,
                  controller: name,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Nome da criança — visível no painel da família',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Informe o nome.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  enabled: !busy,
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail próprio do menor',
                  ),
                  validator: (v) =>
                      v == null ||
                          !v.contains('@') ||
                          v.trim().toLowerCase() ==
                              AppScope.of(context).account!.email.toLowerCase()
                      ? 'Use um e-mail diferente do responsável.'
                      : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    birth == null
                        ? 'Data de nascimento do menor'
                        : '${birth!.day}/${birth!.month}/${birth!.year}',
                  ),
                  onPressed: busy
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final value = await showDatePicker(
                            context: context,
                            firstDate: DateTime(
                              now.year - 18,
                              now.month,
                              now.day,
                            ).add(const Duration(days: 1)),
                            lastDate: now,
                            initialDate:
                                birth ??
                                DateTime(now.year - 12, now.month, now.day),
                          );
                          if (value != null && mounted) {
                            setState(() => birth = value);
                          }
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  enabled: !busy,
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha de acesso do menor',
                  ),
                  validator: (v) => v == null || v.length < 12 || v.length > 128
                      ? 'Use de 12 a 128 caracteres.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  enabled: !busy,
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar senha do menor',
                  ),
                  validator: (v) =>
                      v != password.text ? 'As senhas devem ser iguais.' : null,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: consent,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => consent = v ?? false),
                  title: const Text(
                    'Sou responsável por este menor e autorizo o vínculo e o acesso após as confirmações.',
                  ),
                ),
                if (error != null) ...[
                  const Text(
                    'Se a tentativa anterior criou a conta, retome usando o mesmo e-mail, senha e data de nascimento. A confirmação de e-mail não comprova idade ou parentesco.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                BusyButton(
                  onPressed: submit,
                  busy: busy,
                  label: busy
                      ? 'Criando perfil…'
                      : 'Criar / vincular e enviar confirmação',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
