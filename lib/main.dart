import 'package:flutter/material.dart';
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

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const ConexaoSeguraApp()); }

class ConexaoSeguraApp extends StatefulWidget {
  const ConexaoSeguraApp({super.key, this.state});
  final AppState? state;
  @override
  State<ConexaoSeguraApp> createState() => _ConexaoSeguraAppState();
}
class _ConexaoSeguraAppState extends State<ConexaoSeguraApp> {
  late final AppState state;
  @override
  void initState() { super.initState(); state = widget.state ?? AppState(); state.initialize(); }
  @override
  void dispose() { if (widget.state == null) state.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AppScope(state: state, child: MaterialApp(
    title: 'Conexia Segura', debugShowCheckedModeBanner: false, theme: conexiaTheme(),
    locale: const Locale('pt', 'BR'), supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const SessionGate(),
    onGenerateRoute: (settings) {
      final screens = <String, Widget>{'/login': const LoginScreen(), '/cadastro': const CadastroScreen(), '/inicio': const InicioScreen(), '/seguranca': const SegurancaScreen(), '/perfil-infantil': const PerfilInfantilScreen(), '/painel-responsavel': const PainelResponsavelScreen(), '/denuncia': const DenunciaScreen()};
      return MaterialPageRoute<void>(settings: settings, builder: (_) {
        if (settings.name != '/login' && settings.name != '/cadastro' && state.account == null) return const LoginScreen();
        return screens[settings.name] ?? const SessionGate();
      });
    }));
}
class SessionGate extends StatelessWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return state.account == null ? const LoginScreen() : const InicioScreen();
  }
}
