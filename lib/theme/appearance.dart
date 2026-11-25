import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device preference only; independent of authenticated user data.
class Appearance extends ValueNotifier<bool> {
  Appearance() : super(false);
  static final instance = Appearance();
  static const _storage = FlutterSecureStorage();
  int _revision = 0;
  Future<void> _pending = Future.value();
  Future<void> load() async {
    final revision = _revision;
    try {
      final saved = await _storage.read(key: 'conexia.darkMode');
      if (revision == _revision) value = saved == 'true';
    } catch (_) {
      /* Unavailable storage keeps the default appearance. */
    }
  }

  Future<bool> change(bool dark) async {
    _revision++;
    value = dark;
    try {
      final operation = _pending.then(
        (_) => _storage.write(key: 'conexia.darkMode', value: '$dark'),
      );
      _pending = operation.catchError((Object _) {});
      await operation;
      return true;
    } catch (_) {
      return false;
    }
  }
}

class AppearanceControl extends StatelessWidget {
  const AppearanceControl({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Appearance.instance,
    builder: (context, enabled, _) => SwitchListTile.adaptive(
      title: const Text('Modo escuro'),
      subtitle: const Text(
        'Alterna entre tema claro e escuro. As fotos mantêm suas cores.',
      ),
      secondary: const Icon(Icons.contrast),
      value: enabled,
      onChanged: (value) async {
        final saved = await Appearance.instance.change(value);
        if (!saved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Aparência aplicada nesta sessão. Não foi possível salvar no dispositivo.',
              ),
            ),
          );
        }
      },
    ),
  );
}
