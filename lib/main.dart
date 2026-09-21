import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/cadastro_screen.dart';
import 'screens/seguranca_screen.dart';
import 'screens/inicio_screen.dart';
import 'screens/painel_responsavel_screen.dart';
import 'screens/perfil_infantil_screen.dart';
import 'screens/denuncia_screen.dart';

void main() {
  runApp(const ConexaoSeguraApp());
}

class ConexaoSeguraApp extends StatelessWidget {
  const ConexaoSeguraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Conexão Segura',

      initialRoute: '/login',

      routes: {
        '/login': (context) => const LoginScreen(),
        '/cadastro': (context) => const CadastroScreen(),
         '/seguranca': (context) => const SegurancaScreen(),
        '/inicio': (context) => const InicioScreen(),
        '/perfil-infantil': (context) => const PerfilInfantilScreen(),
        '/painel-responsavel': (context) => const PainelResponsavelScreen(),
        '/denuncia': (context) => const DenunciaScreen(),
      },

      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
    );
  }
}
