import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/capture_cleanup.dart';
import '../widgets/common.dart';

const visionVersion = 'vision-research-v1';
const visionNotice =
    'Participação opcional em um protótipo acadêmico. Estima faixas etárias e sinais de apresentação de foto/tela; pode errar e não comprova identidade, idade ou parentesco. Não altera o acesso ao feed. Capturas processadas em memória; resultados disponíveis por 24 horas, com limpeza periódica dos metadados. Não use fotos de terceiros.';

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});
  @override
  State<VisionScreen> createState() => _VisionState();
}

class _VisionState extends State<VisionScreen> with WidgetsBindingObserver {
  ApiClient? api;
  Future<Map<String, dynamic>>? status;
  CameraController? camera;
  String? session, error;
  List<String> challenge = [];
  final frames = <Uint8List>[];
  Map<String, dynamic>? result;
  bool consent = false, busy = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    api ??= AppScope.of(context).api;
    status ??= api!.request('GET', '/vision/status');
  }

  void cancel() {
    generation++;
    busy = false;
    final id = session;
    session = null;
    frames.clear();
    if (id != null) api?.request('DELETE', '/vision/sessions/$id').ignore();
    final old = camera;
    camera = null;
    old?.dispose().ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Native permission dialogs can temporarily make the app inactive.
    if (state == AppLifecycleState.inactive &&
        busy &&
        camera?.value.isInitialized != true) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      cancel();
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Captura interrompida. Inicie outra sessão ao retornar.';
        });
      }
    }
  }

  Future<void> begin() async {
    if (busy || !consent) return;
    cancel();
    final current = generation;
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      final response = await api!.request('POST', '/vision/sessions', {
        'consent': true,
        'consentVersion': visionVersion,
      });
      if (!mounted || current != generation) {
        api!.request('DELETE', '/vision/sessions/${response['id']}').ignore();
        return;
      }
      session = response['id'] as String;
      challenge = (response['challenge'] as List).cast<String>();
      final cameras = await availableCameras();
      if (!mounted || session == null || current != generation) return;
      if (cameras.isEmpty) {
        throw const ApiException('Nenhuma câmera disponível.');
      }
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final controller = CameraController(
        front.isEmpty ? cameras.first : front.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      camera = controller;
      await controller.initialize();
      if (!mounted || camera != controller) {
        await controller.dispose();
        return;
      }
    } catch (e) {
      if (current != generation) return;
      cancel();
      if (mounted) {
        setState(
          () => error = e is CameraException
              ? 'Permita o acesso à câmera e tente novamente.'
              : e.toString(),
        );
      }
    } finally {
      if (mounted && current == generation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> capture() async {
    final controller = camera;
    final id = session;
    final current = generation;
    if (busy || controller == null || id == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await controller.takePicture();
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } finally {
        await discardCapture(file.path);
      }
      if (!mounted || session != id) return;
      if (bytes.length > 650000) {
        throw const ApiException(
          'Captura muito grande. Use uma câmera com resolução menor.',
        );
      }
      frames.add(bytes);
      if (frames.length == 3) {
        final payload = frames.map(base64Encode).toList();
        frames.clear();
        final old = camera;
        camera = null;
        await old?.dispose();
        late Map<String, dynamic> response;
        try {
          response = await api!.request(
            'POST',
            '/vision/sessions/$id/capture',
            {'frames': payload},
          );
        } finally {
          payload.clear();
        }
        if (!mounted || session != id) return;
        result = response['result'] as Map<String, dynamic>;
        session = null;
      } else {
        // Guidance pacing only. The server independently enforces session time.
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      if (current != generation) return;
      cancel();
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted && current == generation) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Laboratório de verificação etária')),
    body: ContentFrame(
      width: 560,
      child: FutureBuilder<Map<String, dynamic>>(
        future: status,
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() {
                  status = api!.request('GET', '/vision/status');
                  status!.ignore();
                }),
                child: const Text('Tentar novamente'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Experimento acadêmico',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(visionNotice),
              const SizedBox(height: 12),
              const Text(
                'Use boa iluminação, sem filtros e com apenas seu rosto no enquadramento. Movimentos são uma heurística de pesquisa; câmera virtual, vídeos e trocas de pessoa ainda podem enganar o protótipo.',
              ),
              if (snapshot.data!['enabled'] != true)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Os modelos ainda não estão ativados nesta API. O cadastro e o feed continuam funcionando normalmente.',
                  ),
                )
              else ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: consent,
                  onChanged: busy || session != null
                      ? null
                      : (v) => setState(() => consent = v ?? false),
                  title: const Text(
                    'Li as limitações e aceito participar deste experimento opcional.',
                  ),
                ),
                if (camera?.value.isInitialized == true) ...[
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: camera!.value.aspectRatio,
                    child: CameraPreview(camera!),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${frames.length + 1}/3 - ${{'front': 'Olhe de frente', 'left': 'Vire levemente para a esquerda da imagem', 'right': 'Vire levemente para a direita da imagem'}[challenge[frames.length]]}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  FilledButton(
                    onPressed: busy ? null : capture,
                    child: Text(busy ? 'Processando…' : 'Capturar esta etapa'),
                  ),
                ] else
                  FilledButton(
                    onPressed: busy || !consent ? null : begin,
                    child: Text(
                      busy ? 'Processando…' : 'Iniciar captura pela câmera',
                    ),
                  ),
                if (session != null)
                  TextButton(
                    onPressed: () => setState(cancel),
                    child: const Text('Cancelar e descartar capturas'),
                  ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (result != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result!['result'] == 'presentation_risk'
                              ? 'Sinal de risco de apresentação'
                              : result!['result'] == 'experimental_signals_only'
                              ? 'Sinais experimentais observados'
                              : 'Resultado inconclusivo',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (result!['ageBand'] != null)
                          Text(
                            'Faixa estimada pelo modelo: ${result!['ageBand']} anos',
                          ),
                        if (result!['padScore'] is num)
                          Text(
                            'Pontuação PAD: ${(result!['padScore'] as num).toStringAsFixed(3)} (não calibrada)',
                          ),
                        const SizedBox(height: 12),
                        const Text(
                          'Este resultado não é uma aprovação e não altera o acesso ao aplicativo.',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class VisionConsentScreen extends StatefulWidget {
  const VisionConsentScreen({super.key, required this.childId});
  final String childId;
  @override
  State<VisionConsentScreen> createState() => _ConsentState();
}

class _ConsentState extends State<VisionConsentScreen> {
  Future<Map<String, dynamic>>? future;
  bool busy = false;
  String get path =>
      '/vision/children/${Uri.encodeComponent(widget.childId)}/consent';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= AppScope.of(context).api.request('GET', path);
  }

  Future<void> save(bool granted) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await AppScope.of(context).api.request('POST', path, {
        'granted': granted,
        'consentVersion': visionVersion,
      });
      if (mounted) {
        setState(() {
          future = AppScope.of(context).api.request('GET', path);
          future!.ignore();
        });
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Autorização do experimento')),
    body: ContentFrame(
      width: 560,
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (_, snapshot) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(visionNotice),
            const SizedBox(height: 16),
            const Text(
              'Autorizar permite que o menor escolha participar. Revogar cancela as sessões e remove os resultados experimentais desse perfil. Esta autorização não é comprovação de responsabilidade legal.',
            ),
            const SizedBox(height: 24),
            if (snapshot.hasError)
              Text(snapshot.error.toString())
            else if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(
                snapshot.data!['granted'] == true
                    ? 'Participação autorizada'
                    : 'Participação não autorizada',
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => save(snapshot.data!['granted'] != true),
                child: Text(
                  busy
                      ? 'Salvando…'
                      : snapshot.data!['granted'] == true
                      ? 'Revogar e excluir resultados'
                      : 'Autorizar participação experimental',
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
