import 'package:flutter/material.dart';

import '../widgets/common.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    this.recovery = false,
    this.developmentToken,
  });
  final bool recovery;
  final String? developmentToken;
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with WidgetsBindingObserver {
  final email = TextEditingController(),
      code = TextEditingController(),
      password = TextEditingController();
  bool busy = false;
  String? message, development;
  @override
  void initState() {
    super.initState();
    development = widget.developmentToken;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    email.dispose();
    code.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed &&
        mounted &&
        !widget.recovery &&
        AppScope.of(context).usesFirebase &&
        !busy) {
      firebaseAction(false);
    }
  }

  Future<void> action(bool send) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final api = AppScope.of(context).api;
      final result = await api.request(
        'POST',
        send
            ? '/auth/recover'
            : widget.recovery
            ? '/auth/reset'
            : '/auth/verify',
        send
            ? {'email': email.text}
            : {
                'token': code.text,
                if (widget.recovery) 'password': password.text,
              },
      );
      if (!mounted) return;
      setState(() {
        message = result['message'] as String?;
        development = result['developmentToken'] as String?;
      });
      if (!send) {
        password.clear();
        showFeedback(context, message ?? 'Concluído');
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> firebaseAction(bool send) async {
    if (busy) return;
    final state = AppScope.of(context);
    final version = state.api.sessionVersion;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (widget.recovery) {
        if (!email.text.contains('@')) {
          throw const FormatException('Informe seu e-mail.');
        }
        await state.auth!.recover(email.text);
        state.api.checkSession(version);
        if (mounted) {
          setState(
            () => message = 'Se a conta existir, você receberá um link para redefinir a senha. Confira também o spam.',
          );
        }
      } else if (send) {
        await state.sendVerificationEmail();
        if (mounted) {
          setState(
            () => message = 'Link de confirmação enviado. Confira sua caixa de entrada e o spam.',
          );
        }
      } else {
        await state.reloadAccount();
        if (!mounted) return;
        if (state.account?.verified != true) {
          setState(
            () => message = 'O e-mail ainda não foi confirmado. Abra o link recebido e tente novamente.',
          );
        } else {
          Navigator.pushNamedAndRemoveUntil(context, '/inicio', (_) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException ? e.message : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget firebaseBody() {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recovery ? 'Recuperar acesso' : 'Confirmar e-mail'),
      ),
      body: ContentFrame(
        width: 520,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              widget.recovery
                  ? Icons.lock_reset
                  : Icons.mark_email_unread_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              widget.recovery
                  ? 'Receba um link para escolher uma nova senha.'
                  : 'Envie o link de confirmação para ${state.auth!.email ?? "seu e-mail"}. Depois de abrir o link, volte aqui e toque em Já confirmei.',
            ),
            if (!widget.recovery) ...[
              const SizedBox(height: 12),
              const Text(
                'A confirmação do e-mail valida o acesso à caixa postal. Para menores, o feed também depende da confirmação do responsável, do vínculo ativo e da escolha do apelido.',
              ),
            ],
            const SizedBox(height: 20),
            if (widget.recovery)
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : () => firebaseAction(true),
              child: Text(
                busy
                    ? 'Aguarde…'
                    : widget.recovery
                    ? 'Enviar link de recuperação'
                    : 'Enviar / reenviar confirmação',
              ),
            ),
            if (!widget.recovery) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy ? null : () => firebaseAction(false),
                child: const Text('Já confirmei'),
              ),
            ],
            if (widget.recovery)
              TextButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (_) => false,
                ),
                child: const Text('Voltar ao login'),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(message!),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppScope.of(context).usesFirebase
      ? firebaseBody()
      : Scaffold(
          appBar: AppBar(
            title: Text(
              widget.recovery ? 'Recuperar acesso' : 'Confirmar e-mail',
            ),
          ),
          body: ContentFrame(
            width: 520,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Os códigos expiram em uma hora e só podem ser usados uma vez.',
                ),
                const SizedBox(height: 20),
                if (widget.recovery) ...[
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy ? null : () => action(true),
                    child: const Text('Solicitar recuperação'),
                  ),
                  const SizedBox(height: 24),
                ],
                if (development != null) ...[
                  const Text(
                    'AMBIENTE LOCAL: nenhum e-mail foi enviado. Código de desenvolvimento:',
                  ),
                  SelectableText(development!),
                  const SizedBox(height: 20),
                ],
                TextField(
                  controller: code,
                  decoration: const InputDecoration(
                    labelText: 'Código de verificação',
                  ),
                ),
                if (widget.recovery) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nova senha (12 a 128 caracteres)',
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : () => action(false),
                  child: Text(busy ? 'Aguarde…' : 'Confirmar'),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(message!),
                  ),
              ],
            ),
          ),
        );
}
