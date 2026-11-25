import '../widgets/social/profile_heading.dart';
import '../widgets/design_system.dart';
import '../theme/design_tokens.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/common.dart';
import 'social/feed_screen.dart';

class PerfilInfantilScreen extends StatefulWidget {
  const PerfilInfantilScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<PerfilInfantilScreen> createState() => _ProfileState();
}

class _ProfileState extends State<PerfilInfantilScreen> {
  bool busy = false;
  int? count;
  bool hasMore = false;
  Future<void> photo({bool remove = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final state = AppScope.of(context);
      final version = state.api.sessionVersion;
      if (remove) {
        await state.api.request('DELETE', '/me/avatar');
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          imageQuality: 85,
        );
        if (!mounted || file == null) return;
        state.api.checkSession(version);
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        state.api.checkSession(version);
        if (bytes.length > 5 * 1024 * 1024) {
          throw FormatException('Escolha uma foto de até 5 MB.');
        }
        final mime = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
            ? 'image/png'
            : bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216
            ? 'image/jpeg'
            : bytes.length >= 12 &&
                  ascii.decode(bytes.sublist(0, 4), allowInvalid: true) ==
                      'RIFF' &&
                  ascii.decode(bytes.sublist(8, 12), allowInvalid: true) ==
                      'WEBP'
            ? 'image/webp'
            : null;
        if (mime == null) throw FormatException('Use JPEG, PNG ou WebP.');
        final media = await state.api.request('POST', '/media', {
          'mime': mime,
          'data': base64Encode(bytes),
        });
        if (!mounted) return;
        state.api.checkSession(version);
        await state.api.request('POST', '/me/avatar', {'media': media['id']});
      }
      state.api.checkSession(version);
      await state.reloadAccount();
      state.social.invalidate();
      if (mounted) {
        showFeedback(
          context,
          remove ? 'Foto removida.' : 'Foto de perfil salva.',
        );
      }
    } catch (e) {
      if (mounted) showFeedback(context, e is FormatException ? e.message : e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).account;
    if (user == null) {
      return EmptyState(message: 'Entre para ver seu perfil.');
    }
    final body = HeaderBody(
      header: SurfaceCard(
        margin: EdgeInsets.fromLTRB(16, 16, 16, 24),
        padding: EdgeInsets.all(24),
        gradient: ConexiaPalette.of(context).hero,
        child: Column(
          children: [
            ProfileHeading(
              name: user.name,
              bio: user.bio,
              private: user.private,
              media: user.avatar,
              count: count,
              hasMore: hasMore,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: busy ? null : () => photo(),
                  icon: Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    busy
                        ? 'Salvando…'
                        : user.avatar == null
                        ? 'Adicionar foto'
                        : 'Trocar foto',
                  ),
                ),
                if (user.avatar != null)
                  TextButton(
                    onPressed: busy ? null : () => photo(remove: true),
                    child: Text('Remover foto'),
                  ),
              ],
            ),
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/seguranca'),
              icon: Icon(Icons.edit_outlined),
              label: Text('Editar apelido e preferências'),
            ),
          ],
        ),
      ),
      body: FeedScreen(
        ownOnly: true,
        onSummary: (value, more) {
          if (mounted) {
            setState(() {
              count = value;
              hasMore = more;
            });
          }
        },
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: Text('Meu perfil')),
            body: ContentFrame(child: body),
          );
  }
}
