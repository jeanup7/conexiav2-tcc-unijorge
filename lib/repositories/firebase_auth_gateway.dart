import 'package:firebase_auth/firebase_auth.dart';

import '../core/api_client.dart';

abstract class AuthGateway {
  bool get signedIn;
  String? get email;
  Future<void> register(String email, String password);
  Future<void> login(String email, String password);
  Future<String> token({bool force = false});
  Future<void> reload();
  Future<void> sendVerification();
  Future<void> recover(String email);
  Future<void> reauthenticate(String password);
  Future<void> signOut();
}

abstract class AuthSessionEvents {
  String? get identity;
  Stream<String?> get identityChanges;
}

class FirebaseAuthGateway implements AuthGateway, AuthSessionEvents {
  FirebaseAuthGateway(this.auth);
  final FirebaseAuth auth;
  @override
  String? get identity => auth.currentUser?.uid;
  @override
  Stream<String?> get identityChanges =>
      auth.authStateChanges().map((user) => user?.uid).distinct();
  @override
  bool get signedIn => auth.currentUser != null;
  @override
  String? get email => auth.currentUser?.email;
  Future<T> handle<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw ApiException(
        switch (e.code) {
          'email-already-in-use' => 'Este e-mail já está cadastrado no Firebase. Entre ou recupere sua senha.',
          'invalid-email' => 'Informe um e-mail válido.',
          'weak-password' => 'Escolha uma senha mais forte.',
          'invalid-credential' ||
          'wrong-password' ||
          'user-not-found' => 'E-mail ou senha incorretos.',
          'too-many-requests' =>
            'Muitas tentativas. Aguarde antes de tentar novamente.',
          'network-request-failed' => 'Verifique sua conexão com a internet.',
          'operation-not-allowed' =>
            'Ative E-mail/senha em Authentication no console Firebase.',
          'user-disabled' => 'Esta conta foi desativada.',
          _ => 'Não foi possível concluir no Firebase (${e.code}).',
        },
        const {
              'user-disabled',
              'user-token-expired',
              'invalid-user-token',
            }.contains(e.code)
            ? 401
            : 0,
      );
    }
  }

  @override
  Future<void> register(String email, String password) => handle(() async {
    // Retrying after a backend failure must not create a second Firebase account.
    if (this.email?.toLowerCase() == email.trim().toLowerCase()) {
      await reauthenticate(password);
    } else {
      try {
        await auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
        // Finish a registration interrupted between Firebase and our API.
        await auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      }
    }
  });
  @override
  Future<void> login(String email, String password) => handle(() async {
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  });
  @override
  Future<String> token({bool force = false}) => handle(() async {
    final token = await auth.currentUser?.getIdToken(force);
    if (token == null) throw const ApiException('Entre novamente.', 401);
    return token;
  });
  @override
  Future<void> reload() => handle(() async {
    await auth.currentUser?.reload();
  });
  @override
  Future<void> sendVerification() => handle(() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const ApiException('Entre para reenviar a confirmação.');
    }
    await auth.setLanguageCode('pt');
    await user.sendEmailVerification();
  });
  @override
  Future<void> recover(String email) => handle(() async {
    await auth.setLanguageCode('pt');
    await auth.sendPasswordResetEmail(email: email.trim());
  });
  @override
  Future<void> reauthenticate(String password) => handle(() async {
    final user = auth.currentUser;
    if (user == null || user.email == null) {
      throw const ApiException('Entre novamente.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
  });
  @override
  Future<void> signOut() => auth.signOut();
}
