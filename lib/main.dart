import 'dart:async';

import 'repositories/child_registration.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'repositories/firebase_auth_gateway.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/app_state.dart';
import 'widgets/common.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/cadastro_screen.dart';
import 'screens/inicio_screen.dart';
import 'screens/seguranca_screen.dart';
import 'screens/perfil_infantil_screen.dart';
import 'screens/painel_responsavel_screen.dart';
import 'screens/denuncia_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Lato',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<FirebaseApp> initialization = initialize();
  Future<FirebaseApp> initialize() async =>
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  @override
  Widget build(BuildContext context) => FutureBuilder<FirebaseApp>(
    future: initialization,
    builder: (_, snapshot) {
      if (snapshot.hasData) return const ConexaoSeguraApp();
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: conexiaTheme(),
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Não foi possível iniciar o aplicativo. Confira sua conexão e tente novamente.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              setState(() => initialization = initialize()),
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

class ConexaoSeguraApp extends StatefulWidget {
  const ConexaoSeguraApp({super.key, this.state});
  final AppState? state;
  @override
  State<ConexaoSeguraApp> createState() => _ConexaoSeguraAppState();
}

class _ConexaoSeguraAppState extends State<ConexaoSeguraApp>
    with WidgetsBindingObserver {
  late final AppState state;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Timer? permissionTimer;
  String? previousUser;
  bool previousActive = false;
  void sessionChanged() {
    final user = state.account;
    final discardRoutes =
        previousUser != null &&
        (previousUser != user?.id || (previousActive && user?.active != true));
    previousUser = user?.id;
    previousActive = user?.active == true;
    if (discardRoutes && mounted) {
      setState(() => navigatorKey = GlobalKey<NavigatorState>());
    }
  }

  Future<void> checkPermissions() async {
    if (state.account == null ||
        state.loading ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    try {
      await state.reloadAccount();
    } catch (_) {
      /* Offline is recoverable; expired sessions are cleared by AppState. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) unawaited(checkPermissions());
  }

  @override
  void initState() {
    super.initState();
    state =
        widget.state ??
        AppState(
          auth: FirebaseAuthGateway(FirebaseAuth.instance),
          childRegistration: FirebaseChildRegistration(),
        );
    previousUser = state.account?.id;
    previousActive = state.account?.active == true;
    state.addListener(sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    permissionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(checkPermissions());
      }
    });
    unawaited(state.initialize());
  }

  @override
  void dispose() {
    permissionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(sessionChanged);
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Conexia Segura',
      debugShowCheckedModeBanner: false,
      theme: conexiaTheme(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const SessionGate(),
      onGenerateRoute: (settings) {
        final screens = <String, Widget>{
          '/login': const LoginScreen(),
          '/cadastro': const CadastroScreen(),
          '/inicio': const InicioScreen(),
          '/seguranca': const SegurancaScreen(),
          '/perfil-infantil': const PerfilInfantilScreen(),
          '/painel-responsavel': const PainelResponsavelScreen(),
          '/denuncia': const DenunciaScreen(),
        };
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) {
            final current = AppScope.of(context).account;
            if (settings.name != '/login' &&
                settings.name != '/cadastro' &&
                current == null) {
              return const LoginScreen();
            }
            return screens[settings.name] ?? const SessionGate();
          },
        );
      },
    ),
  );
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return state.account == null ? const LoginScreen() : const InicioScreen();
  }
}
