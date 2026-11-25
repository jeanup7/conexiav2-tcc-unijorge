import '../widgets/design_system.dart';
import '../theme/design_tokens.dart';
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
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await AppScope.of(context).login(email.text.trim(), password.text);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/inicio', (_) => false);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: BoxDecoration(gradient: ConexiaPalette.of(context).hero),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: PageReveal(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: BrandMark()),
                    SizedBox(height: 28),
                    Text(
                      'Seu mundo.\nBoas conexões.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontSize: 34,
                            height: 1.12,
                            letterSpacing: -1.1,
                          ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Um espaço para criar, aprender e crescer junto.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: ConexiaPalette.of(context).muted),
                    ),
                    SizedBox(height: 28),
                    SurfaceCard(
                      padding: EdgeInsets.all(24),
                      child: Form(
                        key: form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Bem-vindo de volta',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Entre para continuar suas conexões.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SizedBox(height: 24),
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: [AutofillHints.username],
                              decoration: InputDecoration(
                                labelText: 'E-mail',
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                              validator: (v) => v == null || !v.contains('@')
                                  ? 'Informe seu e-mail'
                                  : null,
                            ),
                            SizedBox(height: 16),
                            TextFormField(
                              controller: password,
                              obscureText: obscure,
                              textInputAction: TextInputAction.done,
                              autofillHints: [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Senha',
                                prefixIcon: Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: obscure
                                      ? 'Mostrar senha'
                                      : 'Ocultar senha',
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(
                                    obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Informe sua senha'
                                  : null,
                              onFieldSubmitted: (_) {
                                if (!busy) login();
                              },
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => VerificationScreen(
                                            recovery: true,
                                          ),
                                        ),
                                      ),
                                child: Text('Esqueci minha senha'),
                              ),
                            ),
                            if (error != null) ...[
                              InlineNotice(message: error!, error: true),
                              SizedBox(height: 16),
                            ],
                            BusyButton(
                              label: busy ? 'Entrando…' : 'Entrar',
                              busy: busy,
                              onPressed: login,
                              icon: Icons.arrow_forward_rounded,
                            ),
                            SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => Navigator.pushNamed(
                                      context,
                                      '/cadastro',
                                    ),
                              icon: Icon(Icons.person_add_alt, size: 19),
                              label: Text('Criar uma conta'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Center(
                      child: StatusPill(
                        label: 'Privacidade desde a primeira conexão',
                        positive: true,
                      ),
                    ),
                    if (FeedPreviewScreen.available)
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => FeedPreviewScreen(),
                                ),
                              ),
                        icon: Icon(Icons.visibility_outlined, size: 18),
                        label: Text('Ver prévia do feed'),
                      ),
                    SizedBox(height: 8),
                    Text(
                      'Conexia Segura • Crie. Conecte. Cuide.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
