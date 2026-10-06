import 'social/feed_preview_screen.dart';
import 'package:flutter/material.dart';
import '../widgets/common.dart';
import 'verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, obscure = true;
  String? error;
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  Future<void> login() async {
    if (!form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      await AppScope.of(context).login(email.text.trim(), password.text);
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/inicio', (_) => false);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Container(
    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEAF0FF), Color(0xFFF8FAFF), Color(0xFFE8F8F5)])),
    child: SafeArea(child: Center(child: ContentFrame(width: 460, child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircleAvatar(radius: 44, backgroundColor: Color(0xFF4965E8), child: Icon(Icons.shield_rounded, color: Colors.white, size: 48)),
      const SizedBox(height: 24), Text('Conexia Segura', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8), const Text('Crie. Conecte. Cuide.', textAlign: TextAlign.center), const SizedBox(height: 32),
      TextFormField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.alternate_email)), validator: (v) => v == null || !v.contains('@') ? 'Informe seu e-mail' : null),
      const SizedBox(height: 16), TextFormField(controller: password, obscureText: obscure, autofillHints: const [AutofillHints.password], decoration: InputDecoration(labelText: 'Senha', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(tooltip: obscure ? 'Mostrar senha' : 'Ocultar senha', onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (v) => v == null || v.isEmpty ? 'Informe sua senha' : null, onFieldSubmitted: (_) { if (!busy) login(); }),
      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: busy ? null : () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const VerificationScreen(recovery: true))), child: const Text('Esqueci minha senha'))),
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error), semanticsLabel: 'Erro: $error')),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : login, child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'))),
      const SizedBox(height: 12), SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: busy ? null : () => Navigator.pushNamed(context, '/cadastro'), icon: const Icon(Icons.person_add_alt), label: const Text('Criar uma conta'))),
      if (FeedPreviewScreen.available) TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const FeedPreviewScreen())), icon: const Icon(Icons.visibility_outlined), label: const Text('Ver prévia do feed')),
      const SizedBox(height: 24), const Text('Seu perfil começa privado. Sua segurança faz parte de cada conexão.', textAlign: TextAlign.center),
    ]))))))));
}
