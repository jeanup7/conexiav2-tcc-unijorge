import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/capture_cleanup.dart';
import '../widgets/common.dart';

const reviewVersion = 'enrollment-review-v1';
const reviewNotice =
    'Autorização específica para revisão humana. A foto será armazenada temporariamente, criptografada, e consultada por administradores autorizados, junto a dados mínimos do cadastro. Não vira foto de perfil. Fica disponível por até 48 horas e é descartada ao concluir a decisão ou revogar; a limpeza periódica pode levar mais uma hora. A revisão não comprova idade, identidade ou parentesco.';
const reviewLabels = {
  'not_submitted': 'Envio ainda não realizado',
  'pending': 'Aguardando análise',
  'correction': 'Nova captura ou correção solicitada',
  'additional_review': 'Em análise adicional',
  'approved': 'Cadastro aprovado',
  'revoked': 'Autorização revogada',
  'superseded': 'Captura substituída',
};
String reviewDate(dynamic value) {
  if (value is! num) return '';
  final d = DateTime.fromMillisecondsSinceEpoch((value * 1000).round())
      .toLocal();
  String n(int v) => '$v'.padLeft(2, '0');
  return '${n(d.day)}/${n(d.month)}/${d.year} ${n(d.hour)}:${n(d.minute)}';
}

Future<T> observeReview<T>(Future<T> future) {
  future.ignore();
  return future;
}

class EnrollmentReviewScreen extends StatefulWidget {
  const EnrollmentReviewScreen({super.key, this.childId, this.childName});
  final String? childId, childName;
  @override
  State<EnrollmentReviewScreen> createState() => _EnrollmentState();
}

class _EnrollmentState extends State<EnrollmentReviewScreen> {
  Future<Map<String, dynamic>>? future;
  bool busy = false;
  bool get parent => widget.childId != null;
  String get path => parent
      ? '/enrollment/children/${Uri.encodeComponent(widget.childId!)}/status'
      : '/enrollment/status';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= observeReview(AppScope.of(context).api.request('GET', path));
  }

  void reload() => setState(() {
    future = observeReview(AppScope.of(context).api.request('GET', path));
  });
  Future<void> authorize(bool granted) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          granted ? 'Autorizar revisão do cadastro?' : 'Revogar autorização?',
        ),
        content: SingleChildScrollView(
          child: Text(
            granted ? reviewNotice : 'A captura será descartada e o acesso social ficará bloqueado. Uma nova liberação exigirá novo envio e revisão.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await AppScope.of(context).api.request(
        'POST',
        '/enrollment/children/${widget.childId}/consent',
        {'granted': granted, 'consentVersion': reviewVersion},
      );
      if (mounted) reload();
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        parent
            ? 'Cadastro de ${widget.childName ?? "perfil vinculado"}'
            : 'Revisão do meu cadastro',
      ),
      actions: [
        IconButton(
          tooltip: 'Atualizar revisão',
          onPressed: busy ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ContentFrame(
      width: 620,
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.error.toString()),
                  TextButton(
                    onPressed: reload,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          final data = snapshot.data!;
          final checks = data['checks'] as Map? ?? {};
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                reviewLabels[data['state']] ?? 'Em acompanhamento',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(reviewNotice),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  checks['childEmail'] == true
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                ),
                title: const Text('E-mail do menor confirmado'),
              ),
              ListTile(
                leading: Icon(
                  checks['family'] == true
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                ),
                title: const Text('Responsável confirmado e vínculo ativo'),
              ),
              ListTile(
                leading: Icon(
                  data['authorized'] == true
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                ),
                title: const Text('Autorização específica para revisão'),
              ),
              if ((data['reason'] as String? ?? '').isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Orientação da revisão: ${data['reason']}'),
                  ),
                ),
              if (data['updated'] != null)
                Text('Atualização: ${reviewDate(data['updated'])}'),
              if (parent)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => authorize(data['authorized'] != true),
                  child: Text(
                    busy
                        ? 'Salvando…'
                        : data['authorized'] == true
                        ? 'Revogar e descartar captura'
                        : 'Autorizar armazenamento e revisão',
                  ),
                )
              else if (data['authorized'] == true &&
                  checks['childEmail'] == true &&
                  checks['family'] == true &&
                  data['state'] != 'approved')
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const EnrollmentCaptureScreen(),
                      ),
                    );
                    if (mounted) reload();
                  },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    data['state'] == 'not_submitted'
                        ? 'Tirar foto para revisão'
                        : 'Enviar nova captura / pedir reanálise',
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Enquanto aguarda, você pode acompanhar o cadastro e consultar as orientações de segurança. Feed, pesquisa de perfis, publicações e mensagens dependem da liberação e das demais verificações.',
              ),
              const SizedBox(height: 24),
              Text(
                'Histórico da solicitação',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final item in data['history'] as List? ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item['action'] == 'capture.submitted'
                        ? 'Captura recebida'
                        : item['action'] == 'capture.read'
                        ? 'Captura consultada por revisor autorizado'
                        : item['action'] == 'consent.revoked'
                        ? 'Autorização revogada'
                        : item['action'] == 'capture.expired'
                        ? 'Captura expirada'
                        : reviewLabels[(item['action'] as String).replaceFirst(
                                'decision.',
                                '',
                              )] ??
                              'Revisão atualizada',
                  ),
                  subtitle: Text(
                    '${reviewDate(item['created'])}\n${item['reason']}',
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class EnrollmentCaptureScreen extends StatefulWidget {
  const EnrollmentCaptureScreen({super.key});
  @override
  State<EnrollmentCaptureScreen> createState() => _CaptureState();
}

class _CaptureState extends State<EnrollmentCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  ApiClient? api;
  String? ticket, error;
  bool accepted = false, busy = false;
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
  }

  void cancel() {
    generation++;
    final id = ticket;
    ticket = null;
    final c = camera;
    camera = null;
    c?.dispose().ignore();
    if (id != null) api?.request('DELETE', '/enrollment/tickets/$id').ignore();
    busy = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive &&
        busy &&
        camera?.value.isInitialized != true) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      cancel();
      if (mounted) {
        setState(() => error = 'Captura interrompida. Inicie novamente.');
      }
    }
  }

  Future<void> begin() async {
    if (busy || !accepted) return;
    cancel();
    final current = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await api!.request('POST', '/enrollment/tickets', {
        'consent': true,
        'consentVersion': reviewVersion,
      });
      if (!mounted || current != generation) {
        api!.request('DELETE', '/enrollment/tickets/${value['id']}').ignore();
        return;
      }
      ticket = value['id'] as String;
      final cameras = await availableCameras();
      if (!mounted || current != generation) return;
      if (cameras.isEmpty) {
        throw const ApiException('Nenhuma câmera disponível.');
      }
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final c = CameraController(
        front.isEmpty ? cameras.first : front.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      camera = c;
      await c.initialize();
      if (!mounted || camera != c) {
        await c.dispose();
        return;
      }
    } catch (e) {
      if (current == generation) {
        cancel();
        if (mounted) {
          setState(
            () => error = e is CameraException
                ? 'Permita o uso da câmera para continuar.'
                : e.toString(),
          );
        }
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (busy || camera == null || ticket == null) return;
    final id = ticket!;
    final current = generation;
    setState(() => busy = true);
    try {
      final file = await camera!.takePicture();
      late String encoded;
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length > 650000) {
          throw const ApiException('Captura muito grande.');
        }
        encoded = base64Encode(bytes);
      } finally {
        await discardCapture(file.path);
      }
      if (!mounted || current != generation) return;
      final old = camera;
      camera = null;
      await old?.dispose();
      await api!.request('POST', '/enrollment/tickets/$id', {'image': encoded});
      encoded = '';
      if (!mounted || current != generation) return;
      ticket = null;
      await AppScope.of(context).reloadAccount();
      if (mounted) {
        showFeedback(
          context,
          'Captura recebida. Aguarde a revisão do cadastro.',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (current == generation) {
        cancel();
        if (mounted) setState(() => error = e.toString());
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Captura para revisão')),
    body: ContentFrame(
      width: 560,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(reviewNotice),
          const SizedBox(height: 16),
          const Text(
            'Use boa iluminação, mostre apenas seu rosto e não envie documentos ou informações pessoais na imagem. A interface usa a câmera, mas não garante a origem ou autenticidade da foto.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: accepted,
            onChanged: busy || ticket != null
                ? null
                : (v) => setState(() => accepted = v ?? false),
            title: const Text(
              'Entendi e aceito enviar minha captura para revisão humana.',
            ),
          ),
          if (camera?.value.isInitialized == true) ...[
            AspectRatio(
              aspectRatio: camera!.value.aspectRatio,
              child: CameraPreview(camera!),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : send,
              child: Text(busy ? 'Enviando…' : 'Tirar e enviar foto'),
            ),
          ] else
            FilledButton(
              onPressed: busy || !accepted ? null : begin,
              child: Text(busy ? 'Aguarde…' : 'Abrir câmera para revisão'),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}

class AdminEnrollmentScreen extends StatefulWidget {
  const AdminEnrollmentScreen({super.key});
  @override
  State<AdminEnrollmentScreen> createState() => _QueueState();
}

class _QueueState extends State<AdminEnrollmentScreen> {
  Future<Map<String, dynamic>>? future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppScope.of(context).account?.isAdmin == true) {
      future ??= observeReview(
        AppScope.of(context).api.request('GET', '/admin/enrollments'),
      );
    }
  }

  void reload() => setState(() {
    future = observeReview(
      AppScope.of(context).api.request('GET', '/admin/enrollments'),
    );
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Revisão de cadastros'),
      actions: [
        IconButton(
          tooltip: 'Atualizar cadastros',
          onPressed: reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ContentFrame(
      child: AppScope.of(context).account?.isAdmin != true
          ? const EmptyState(message: 'Acesso restrito à administração.')
          : FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (_, s) {
                if (s.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: reload,
                      child: const Text('Tentar novamente'),
                    ),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = s.data!['items'] as List;
                if (rows.isEmpty) {
                  return const EmptyState(
                    message: 'Nenhum cadastro disponível para revisão. Você não pode analisar sua própria família.',
                  );
                }
                return ListView(
                  children: [
                    for (final row in rows)
                      Card(
                        child: ListTile(
                          title: Text(row['childName'] as String),
                          subtitle: Text(
                            '${reviewLabels[row['state']]}\nResponsável: ${row['guardianName']}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => AdminEnrollmentDetail(
                                  id: row['id'] as String,
                                ),
                              ),
                            );
                            if (mounted) reload();
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
    ),
  );
}

class AdminEnrollmentDetail extends StatefulWidget {
  const AdminEnrollmentDetail({super.key, required this.id});
  final String id;
  @override
  State<AdminEnrollmentDetail> createState() => _DetailState();
}

class _DetailState extends State<AdminEnrollmentDetail>
    with WidgetsBindingObserver {
  Future<Map<String, dynamic>>? future;
  Timer? timer;
  int revision = 0;
  bool busy = false, usable = false, reviewed = false;
  final reason = TextEditingController();
  String get path => '/admin/enrollments/${Uri.encodeComponent(widget.id)}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          !busy &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        reload();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    reason.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= observeReview(AppScope.of(context).api.request('GET', path));
  }

  void reload() => setState(() {
    revision++;
    future = observeReview(AppScope.of(context).api.request('GET', path));
  });
  Future<void> decide(String action) async {
    if (busy) return;
    if (reason.text.trim().length < 10) {
      showFeedback(context, 'Explique a decisão com pelo menos 10 caracteres.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          action == 'approved' ? 'Aprovar cadastro?' : 'Registrar orientação?',
        ),
        content: Text(
          action == 'approved'
              ? 'Você está liberando o cadastro, sem certificar idade ou parentesco. A captura será descartada.'
              : action == 'correction'
              ? 'A família receberá a orientação e a captura será descartada.'
              : 'O cadastro seguirá bloqueado para análise adicional.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirmar decisão'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await AppScope.of(context).api.request('POST', '$path/decision', {
        'action': action,
        'reason': reason.text.trim(),
        'captureUsable': usable,
        'dataReviewed': reviewed,
      });
      if (mounted) {
        showFeedback(context, 'Decisão registrada.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showFeedback(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Analisar cadastro')),
    body: ContentFrame(
      width: 640,
      child: AppScope.of(context).account?.isAdmin != true
          ? const EmptyState(message: 'Acesso restrito.')
          : FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.hasError) {
                  return ListView(
                    children: [
                      EmptyState(message: s.error.toString()),
                      TextButton(
                        onPressed: reload,
                        child: const Text('Atualizar acesso'),
                      ),
                    ],
                  );
                }
                final data = s.data!;
                final c = data['case'] as Map;
                final checks = data['checks'] as Map;
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      c['childName'] as String,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'Idade declarada: ${c['declaredAge']} anos (não comprovada)',
                    ),
                    Text(reviewLabels[c['state']] ?? 'Em acompanhamento'),
                    const SizedBox(height: 16),
                    const Text(
                      'Avalie o cadastro e a legibilidade. Não conclua idade ou parentesco pela aparência. Não faça capturas de tela nem compartilhe a foto.',
                    ),
                    Text(
                      'E-mail do menor confirmado: ${checks['childEmail'] == true ? "sim" : "não"}',
                    ),
                    Text(
                      'Confirmação do responsável e vínculo ativo: ${checks['family'] == true ? "sim" : "não"}',
                    ),
                    if (data['hasPhoto'] == true)
                      ReviewPhotoView(
                        key: ValueKey(revision),
                        endpoint: '$path/photo',
                      )
                    else
                      const EmptyState(
                        message: 'Captura já descartada ou expirada.',
                      ),
                    if ([
                      'pending',
                      'additional_review',
                    ].contains(c['state'])) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: usable,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => usable = v ?? false),
                        title: const Text(
                          'Consultei a captura e ela está legível para esta revisão.',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: reviewed,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => reviewed = v ?? false),
                        title: const Text(
                          'Revisei as confirmações e os dados disponíveis do cadastro.',
                        ),
                      ),
                      TextField(
                        controller: reason,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Motivo / orientação à família',
                          helperText: 'Pelo menos 10 caracteres. Evite dados pessoais de terceiros.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed:
                            busy ||
                                !usable ||
                                !reviewed ||
                                data['hasPhoto'] != true ||
                                checks['childEmail'] != true ||
                                checks['family'] != true
                            ? null
                            : () => decide('approved'),
                        child: const Text('Aprovar cadastro'),
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : () => decide('correction'),
                        child: const Text('Solicitar nova captura ou correção'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => decide('additional_review'),
                        child: const Text('Encaminhar para análise adicional'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Registros da revisão',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final entry in data['history'] as List? ?? [])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${entry['actorName'] ?? "Sistema"} • ${entry['action']}',
                        ),
                        subtitle: Text(
                          '${reviewDate(entry['created'])}\n${entry['reason']}',
                        ),
                      ),
                  ],
                );
              },
            ),
    ),
  );
}

/// Avoid global ImageCache and files for restricted review captures.
class ReviewPhotoView extends StatefulWidget {
  const ReviewPhotoView({super.key, required this.endpoint});
  final String endpoint;
  @override
  State<ReviewPhotoView> createState() => _PhotoState();
}

class _PhotoState extends State<ReviewPhotoView> {
  ui.Image? image;
  bool started = false;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      load();
    }
  }

  Future<void> load() async {
    try {
      final value = await AppScope.of(context).api
          .request('GET', widget.endpoint);
      final codec = await ui.instantiateImageCodec(
        base64Decode(value['data'] as String),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => image = frame.image);
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Captura indisponível. Atualize o cadastro.');
      }
    }
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: error != null
        ? Text(error!)
        : image == null
        ? const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          )
        : SizedBox(
            height: 320,
            child: RawImage(image: image, fit: BoxFit.contain),
          ),
  );
}
