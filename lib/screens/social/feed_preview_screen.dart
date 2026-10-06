import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/common.dart';
import 'feed_screen.dart';

/// Visual sandbox: no authenticated API calls, no change to account approval.
class FeedPreviewScreen extends StatelessWidget {
  const FeedPreviewScreen({super.key});

  static bool get available => kDebugMode &&
      (!kIsWeb || const {'localhost', '127.0.0.1'}.contains(Uri.base.host));

  @override
  Widget build(BuildContext context) {
    if (!available) {
      return const Scaffold(body: EmptyState(message: 'A prévia está disponível apenas no desenvolvimento local.'));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_rounded, color: Color(0xFF6265ED), size: 22),
          SizedBox(width: 7),
          Text('conexia', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
        ]),
        actions: [IconButton(
          tooltip: 'Sobre a prévia',
          icon: const Icon(Icons.info_outline_rounded, size: 23),
          onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
            title: const Text('Uma prévia para experimentar'),
            content: const Text('As quatro fotos enviadas foram incluídas nos arquivos do projeto. Perfis e publicações são demonstrativos; curtidas, comentários e posts ficam em memória. Nenhuma ação é enviada ao servidor. Salvos duram apenas nesta sessão.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
          )),
        ),],
      ),
      body: ContentFrame(width: 600, child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: const BoxDecoration(color: Color(0xFFF0F1FE), border: Border(bottom: BorderSide(color: Color(0xFFE6E8FA)))),
          child: const Row(children: [
            Icon(Icons.science_outlined, size: 14, color: Color(0xFF6A6DB0)),
            SizedBox(width: 7),
            Expanded(child: Text('PRÉVIA LOCAL • Conteúdo de demonstração', style: TextStyle(fontSize: 11, color: Color(0xFF6A6DB0)))),
          ]),
        ),
        const Expanded(child: FeedScreen(preview: true)),
      ])),
    );
  }
}
