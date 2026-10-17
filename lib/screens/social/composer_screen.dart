import '../../models/content_categories.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/models.dart';
import '../../models/preview_content.dart';
import '../../widgets/common.dart';
import '../../widgets/design_system.dart';
import '../../widgets/social/post_gallery.dart';

class ComposerScreen extends StatefulWidget {
  const ComposerScreen({
    super.key,
    this.story = false,
    this.postId,
    this.initialText,
    this.preview = false,
    this.embedded = false,
    this.onCreated,
  });
  final bool story, preview, embedded;
  final String? postId, initialText;
  final ValueChanged<Publication>? onCreated;
  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _PickedPhoto {
  const _PickedPhoto(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

class _ComposerScreenState extends State<ComposerScreen> {
  late final TextEditingController text;
  final List<_PickedPhoto> picked = [];
  final List<String> assets = [];
  String? error;
  bool busy = false, picking = false;
  String category = 'other';
  int get count => picked.length + assets.length;
  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    if (busy || picking) return;
    setState(() => picking = true);
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (!mounted || files.isEmpty) return;
      if (count + files.length > 10) {
        if (mounted) {
          showFeedback(context, 'Escolha até 10 fotos por publicação.');
        }
        return;
      }
      final additions = <_PickedPhoto>[];
      for (final file in files) {
        final value = await file.readAsBytes();
        if (value.length > 5 * 1024 * 1024) {
          throw const FormatException('Cada foto deve ter até 5 MB.');
        }
        final mime = value.length >= 8 && value[0] == 137 && value[1] == 80
            ? 'image/png'
            : value.length >= 3 && value[0] == 255 && value[1] == 216
            ? 'image/jpeg'
            : value.length >= 12 &&
                  ascii.decode(value.sublist(0, 4), allowInvalid: true) ==
                      'RIFF' &&
                  ascii.decode(value.sublist(8, 12), allowInvalid: true) ==
                      'WEBP'
            ? 'image/webp'
            : null;
        if (mime == null) {
          throw const FormatException('Use fotos JPEG, PNG ou WebP.');
        }
        additions.add(_PickedPhoto(value, mime));
      }
      if (mounted) {
        setState(() {
          picked.addAll(additions);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        showFeedback(
          context,
          e is FormatException
              ? e.message
              : 'Não foi possível abrir a galeria. Confira as permissões.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> publish() async {
    if (busy || picking) return;
    final submitted = text.text.trim();
    final selectedPhotos = List<_PickedPhoto>.of(picked);
    final selectedCategory = category;
    if (text.text.trim().isEmpty) {
      setState(() => error = 'Escreva uma legenda.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.preview) {
        final result = Publication(
          id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
          userId: 'preview-self',
          author: 'Você',
          category: category,
          text: text.text.trim(),
          likes: 0,
          liked: false,
          assetImages: List.of(assets),
          localImages: picked.map((p) => p.bytes).toList(),
          expires: widget.story
              ? DateTime.now()
                        .add(const Duration(hours: 24))
                        .millisecondsSinceEpoch /
                    1000
              : null,
        );
        if (widget.onCreated != null) {
          widget.onCreated!(result);
          if (mounted) {
            setState(() {
              text.clear();
              picked.clear();
              assets.clear();
            });
          }
        } else {
          Navigator.pop(context, result);
        }
        return;
      }
      final state = AppScope.of(context);
      final api = state.api;
      final version = api.sessionVersion;
      final ids = <String>[];
      for (final photo in selectedPhotos) {
        final uploaded = await api.request('POST', '/media', {
          'mime': photo.mime,
          'data': base64Encode(photo.bytes),
        });
        if (!mounted) return;
        api.checkSession(version);
        ids.add(uploaded['id'] as String);
      }
      await api.request(
        widget.postId == null ? 'POST' : 'PATCH',
        widget.postId != null
            ? '/posts/${widget.postId}'
            : widget.story
            ? '/stories'
            : '/posts',
        {
          'text': submitted,
          if (widget.postId == null) ...{
            'mediaItems': ids,
            'category': selectedCategory,
          },
        },
      );
      api.checkSession(version);
      state.social.invalidate();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = [
      ...assets.map(PostPhoto.asset),
      ...picked.map((p) => PostPhoto.memory(p.bytes)),
    ];
    final body = ContentFrame(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.embedded) ...[
            Text(
              'Criar publicação',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            widget.preview
                ? 'Experimente publicar até 10 fotos. Tudo fica apenas nesta prévia.'
                : 'Compartilhe ideias, sem expor informações pessoais.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: text,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Legenda'),
          ),
          if (widget.postId == null) ...[
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(
                labelText: 'Categoria da publicação',
              ),
              items: contentCategories.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) => setState(() => category = v ?? 'other'),
            ),
            const SizedBox(height: 12),
            if (!widget.preview)
              const Text(
                'Se um menor visualizar esta publicação, seu responsável vinculado poderá vê-la no acompanhamento familiar enquanto ela continuar disponível para o menor.',
              ),
            const SizedBox(height: 16),
          ],
          if (photos.isNotEmpty) ...[
            PostGallery(
              key: ValueKey(count),
              photos: photos,
              onDoubleTap: () {},
            ),
            Wrap(
              spacing: 8,
              children: List.generate(
                count,
                (i) => InputChip(
                  label: Text('Foto ${i + 1}'),
                  onDeleted: busy
                      ? null
                      : () => setState(() {
                          if (i < assets.length) {
                            assets.removeAt(i);
                          } else {
                            picked.removeAt(i - assets.length);
                          }
                        }),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.postId == null) ...[
            OutlinedButton.icon(
              onPressed: busy || picking || count >= 10 ? null : pick,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Selecionar fotos'),
            ),
            if (widget.preview) ...[
              const SizedBox(height: 16),
              const Text('Ou use as fotos da demonstração:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: previewPublications
                    .map(
                      (p) => InkWell(
                        key: ValueKey('select-${p.assetImage}'),
                        onTap: busy
                            ? null
                            : () => setState(() {
                                if (assets.contains(p.assetImage)) {
                                  assets.remove(p.assetImage);
                                } else if (count < 10) {
                                  assets.add(p.assetImage!);
                                }
                              }),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset(
                                    p.assetImage!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              if (assets.contains(p.assetImage))
                                const Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
          if (widget.story)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Este story expira em 24 horas.'),
            ),
          if (error != null) InlineNotice(message: error!, error: true),
          const SizedBox(height: 20),
          BusyButton(
            busy: busy,
            onPressed: picking ? null : publish,
            label: busy
                ? 'Publicando…'
                : widget.preview
                ? 'Publicar na prévia'
                : 'Publicar',
          ),
        ],
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(
              title: Text(
                widget.postId != null
                    ? 'Editar publicação'
                    : widget.story
                    ? 'Novo story'
                    : 'Criar publicação',
              ),
            ),
            body: body,
          );
  }
}
