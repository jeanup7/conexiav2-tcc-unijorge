import 'package:flutter/material.dart';
import '../widgets/common.dart';
import 'verification_screen.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});
  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}
class _CadastroScreenState extends State<CadastroScreen> {
  final name = TextEditingController(), email = TextEditingController(), password = TextEditingController(), confirm = TextEditingController(), guardian = TextEditingController();
  final form = GlobalKey<FormState>();
  DateTime? birth;
  bool busy = false;
  String? error;
  bool get minor {
    if (birth == null) return true;
    final now = DateTime.now();
    return now.year - birth!.year - ((now.month < birth!.month || (now.month == birth!.month && now.day < birth!.day)) ? 1 : 0) < 18;
  }
  @override
  void dispose() { for (final c in [name,email,password,confirm,guardian]) { c.dispose(); } super.dispose(); }
  Future<void> submit() async {
    if (!form.currentState!.validate() || birth == null) { setState(() => error = 'Revise os campos e informe a data de nascimento.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final result = await AppScope.of(context).api.request('POST','/auth/register', {'name': name.text, 'email': email.text, 'password': password.text, 'birth': birth!.toIso8601String().split('T').first, if (minor) 'guardianEmail': guardian.text});
      password.clear(); confirm.clear();
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => VerificationScreen(developmentToken: result['developmentToken'] as String?)));
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Criar sua conta')), body: ContentFrame(width: 520, child: ListView(padding: const EdgeInsets.all(24), children: [Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Seu espaço começa aqui', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 8), const Text('Use um apelido. Não compartilhe endereço, escola ou telefone no perfil.'), const SizedBox(height: 24),
    TextFormField(controller: name, maxLength: 60, decoration: const InputDecoration(labelText: 'Nome ou apelido'), validator: (v) => v == null || v.trim().isEmpty ? 'Informe um apelido' : null),
    const SizedBox(height: 12), TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail de acesso'), validator: (v) => v == null || !v.contains('@') ? 'Informe um e-mail' : null),
    const SizedBox(height: 16), OutlinedButton.icon(onPressed: busy ? null : () async { final value = await showDatePicker(context: context, firstDate: DateTime(1906), lastDate: DateTime.now(), initialDate: DateTime(2012)); if (value != null && mounted) setState(() => birth = value); }, icon: const Icon(Icons.calendar_month), label: Text(birth == null ? 'Data de nascimento' : '${birth!.day}/${birth!.month}/${birth!.year}')),
    const SizedBox(height: 16), TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Senha — ao menos 12 caracteres'), validator: (v) => v == null || v.length < 12 || v.length > 128 ? 'Use de 12 a 128 caracteres' : null),
    const SizedBox(height: 16), TextFormField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirme a senha'), validator: (v) => v != password.text ? 'As senhas precisam ser iguais' : null),
    if (minor) ...[const SizedBox(height: 24), const Text('Participação do responsável', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('A conta terá acesso restrito até a verificação do vínculo. Informar um e-mail não comprova consentimento ou identidade.'), const SizedBox(height: 16), TextFormField(controller: guardian, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail do responsável'), validator: (v) => v == null || !v.contains('@') || v.trim().toLowerCase() == email.text.trim().toLowerCase() ? 'Informe um e-mail independente' : null)],
    const SizedBox(height: 24), const Text('Coletamos estes dados para acesso e aplicação das proteções por idade. O lançamento depende de aviso de privacidade e fluxos jurídicos validados.'),
    if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    const SizedBox(height: 16), FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Criando…' : 'Criar conta privada')),
  ]))])));
}
