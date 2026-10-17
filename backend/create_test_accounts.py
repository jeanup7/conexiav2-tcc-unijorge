"""Explicit developer fixture: Firebase identities plus local SQLite profiles.

Run with CONEXIA_DEV=1 using the same DATABASE_PATH and credentials as the API.
Only synthetic, reserved example.com identities are created. Email verification
and guardian consent are simulated for these fixtures, never for real accounts.
Passwords are kept outside the checkout and are never printed by this script.
"""
import json
import os
from pathlib import Path
import secrets
import time

from repository import Repository
from security import password_hash, token

SPECS = {
    'teste': ('conexia.teste@example.com', 'Alex • teste', '2000-01-01'),
    'admin': ('conexia.admin@example.com', 'Admin • teste', '1990-01-01'),
    'responsavel': ('conexia.responsavel@example.com', 'Responsável • teste', '1985-01-01'),
    'jovem': ('conexia.jovem@example.com', 'Estrela • teste', '2012-01-01'),
}


def main():
    if os.environ.get('CONEXIA_DEV') != '1' or os.environ.get('FIREBASE_PROJECT_ID') != 'conexiabeta2':
        raise SystemExit('Use CONEXIA_DEV=1 e FIREBASE_PROJECT_ID=conexiabeta2 para criar apenas contas fictícias de teste.')
    import firebase_admin
    from firebase_admin import auth
    app = firebase_admin.initialize_app(options={'projectId': 'conexiabeta2'}, name='conexia-fixtures')
    root = Path(__file__).resolve().parent
    repo = Repository(os.environ.get('DATABASE_PATH', str(root / 'conexia.sqlite3')))
    credential_path = Path.home() / 'Downloads' / 'Conexia-acessos-teste.json'
    if credential_path.exists():
        saved = json.loads(credential_path.read_text(encoding='utf-8'))
        if saved.get('project') != 'conexiabeta2':
            raise SystemExit('O arquivo de acessos existente pertence a outro projeto.')
    else:
        saved = {'project': 'conexiabeta2', 'accounts': {}}
    # Check conflicts before creating anything remotely. Never take over users.
    for role, (email, _, _) in SPECS.items():
        uid = 'conexia-demo-v1-' + role
        local = repo.one('SELECT id FROM users WHERE email=?', (email,))
        if local and local['id'] != uid:
            raise SystemExit('Existe outro cadastro local com o e-mail reservado: ' + email)
        try:
            existing = auth.get_user_by_email(email, app=app)
        except auth.UserNotFoundError:
            existing = None
        if existing and (existing.uid != uid or not (existing.custom_claims or {}).get('conexia_demo')):
            raise SystemExit('Existe outra identidade Firebase com o e-mail reservado: ' + email)
        if existing and role not in saved['accounts']:
            raise SystemExit('Identidade de teste já existe, mas o arquivo de acesso foi perdido: ' + email)
        if role not in saved['accounts']:
            saved['accounts'][role] = {'email': email, 'password': 'Cx!' + secrets.token_urlsafe(15)}
    # Persist before requests so retries keep the same credentials after failures.
    credential_path.write_text(json.dumps(saved, ensure_ascii=False, indent=2), encoding='utf-8')
    for role, (email, name, birth) in SPECS.items():
        uid = 'conexia-demo-v1-' + role
        try:
            identity = auth.get_user(uid, app=app)
        except auth.UserNotFoundError:
            identity = auth.create_user(uid=uid, email=email, password=saved['accounts'][role]['password'], display_name=name, email_verified=True, app=app)
            auth.set_custom_user_claims(uid, {'conexia_demo': True}, app=app)
        if identity.email != email:
            raise SystemExit('UID reservado já está em uso por outra identidade.')
        with repo.db:
            repo.db.execute('''INSERT OR IGNORE INTO users(id,email,password,name,birth,verified,private,messages,bio)
                VALUES(?,?,?,?,?,1,?,1,?)''', (uid,email,password_hash(token()),name,birth,0 if role=='teste' else 1,'Conta fictícia para testes de desenvolvimento.'))
            repo.db.execute('INSERT OR IGNORE INTO firebase_identities VALUES(?,?)', (uid,uid))
    guardian = 'conexia-demo-v1-responsavel'
    child = 'conexia-demo-v1-jovem'
    with repo.db:
        repo.db.execute('INSERT OR IGNORE INTO administrators VALUES(?)', ('conexia-demo-v1-admin',))
        repo.db.execute('INSERT OR IGNORE INTO guardian_links VALUES(?,?,?,?,?,?)', (child,guardian,'Adolescente fictício',1,'active',time.time()))
        # Simulated consent only for the fictional guardian and child themselves.
        for a, b in [(guardian,child),('conexia-demo-v1-teste','conexia-demo-v1-admin')]:
            repo.db.execute('INSERT OR IGNORE INTO contacts VALUES(?,?,1)', (a,b))
            repo.db.execute('INSERT OR IGNORE INTO contacts VALUES(?,?,1)', (b,a))
        repo.db.execute('INSERT INTO audit VALUES(?,?,?,?)', (token(),'development.fixtures.created','local-operator',time.time()))
    # Reusable fixture posts and photos; no fabricated read history or decisions.
    for index, (filename, caption, category) in enumerate([
        ('luffy.jpg', 'Post de teste: aventuras e criatividade. #anime', 'anime'),
        ('peter_parker.jpg', 'Post de teste: uma pausa entre as aulas.', 'education'),
        ('shikamaru_bahia.png', 'Post de teste: esporte também conecta!', 'sports'),
    ]):
        pid = 'conexia-demo-post-' + str(index)
        mid = 'conexia-demo-media-' + str(index)
        asset = root.parent / 'assets' / 'feed' / filename
        with repo.db:
            repo.db.execute('INSERT OR IGNORE INTO media VALUES(?,?,?,?)', (mid,'conexia-demo-v1-teste','image/png' if filename.endswith('.png') else 'image/jpeg',asset.read_bytes()))
            repo.db.execute('INSERT OR IGNORE INTO posts VALUES(?,?,?,?,?,?,?)', (pid,'conexia-demo-v1-teste',caption,mid,0,time.time()-index,None))
            repo.db.execute('INSERT OR IGNORE INTO post_media VALUES(?,?,0)', (pid,mid))
            repo.db.execute('INSERT OR IGNORE INTO post_categories VALUES(?,?)', (pid,category))
    # One initial queue item lets the administrator test the moderation workflow.
    with repo.db:
        repo.db.execute("INSERT OR IGNORE INTO reports(id,user,target,reason,created) VALUES(?,?,?,?,?)", ('conexia-demo-report-1','conexia-demo-v1-admin','conexia-demo-post-2','Denúncia fictícia para testar arquivamento ou remoção pelo administrador.',time.time()))
    repo.db.close()
    print('Quatro contas fictícias preparadas. Confirmação de e-mail e consentimento são simulados somente nestas contas.')
    print('Acessos salvos fora do projeto: ' + str(credential_path))


if __name__ == '__main__':
    main()
