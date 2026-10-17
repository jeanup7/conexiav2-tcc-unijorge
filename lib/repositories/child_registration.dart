import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../core/api_client.dart';
import 'firebase_auth_gateway.dart';

abstract class ChildRegistration {
  Future<bool> create(
    String email,
    String password,
    Future<void> Function(String) save,
  );
}

class FirebaseChildRegistration implements ChildRegistration {
  @override
  Future<bool> create(
    String email,
    String password,
    Future<void> Function(String) save,
  ) async {
    final app = await Firebase.initializeApp(
      name: 'child-${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    final gateway = FirebaseAuthGateway(auth);
    try {
      if (kIsWeb) await auth.setPersistence(Persistence.NONE);
      try {
        await auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
        await gateway.login(email, password);
      }
      await save(await gateway.token());
      try {
        await gateway.sendVerification();
        return true;
      } catch (_) {
        return false;
      } // Profile exists; child can log in and resend the link.
    } on FirebaseAuthException catch (e) {
      throw ApiException(
        'Não foi possível configurar a conta do menor (${e.code}). Confira o e-mail e a senha.',
      );
    } finally {
      // A lost response can follow a committed backend write. Keep the identity
      // so the same credentials can safely retry linking instead of orphaning it.
      try {
        await auth.signOut();
      } catch (_) {
        // Secondary authentication uses non-persistent web storage.
      }
      try {
        await app.delete();
      } catch (_) {
        // Cleanup must not turn a completed registration into a failure.
      }
    }
  }
}
