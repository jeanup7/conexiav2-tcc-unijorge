"""Provision one linked, fictional guardian/child pair for local Firebase QA.

Requires CONEXIA_DEV=1, FIREBASE_PROJECT_ID=conexiabeta2 and QA_PASSWORD.
Credentials are exported outside the repository. Existing passwords are never reset.
"""
import json
import os
import re
import sqlite3
import time
import urllib.error
import urllib.request
from pathlib import Path

from repository import Repository
from service import Service
from firebase_identity import FirebaseIdentity

NAMESPACE = 'conexia-linked-pair-qa-v1'
PEOPLE = {
    'guardian': {'uid': NAMESPACE+'-guardian', 'email': 'responsavel.vinculo.qa@example.com', 'name': 'Mariana Lima Costa', 'birth': '1992-05-14'},
    'child': {'uid': NAMESPACE+'-child', 'email': 'crianca.vinculo.qa@example.com', 'name': 'Lucas Lima Costa', 'birth': '2014-08-20', 'nickname': 'LucaExplora'},
}


def main():
    if os.environ.get('CONEXIA_DEV') != '1' or os.environ.get('FIREBASE_PROJECT_ID') != 'conexiabeta2':
        raise SystemExit('Exclusivo do ambiente local de QA conexiabeta2.')
    password = os.environ['QA_PASSWORD']
    if len(password) < 12:
        raise SystemExit('Use pelo menos 12 caracteres na senha de QA.')
    root = Path(__file__).resolve().parent
    database = Path(os.environ.get('DATABASE_PATH', str(root/'conexia.sqlite3')))
    if not database.is_file():
        raise SystemExit('Banco local não encontrado.')
    import firebase_admin
    from firebase_admin import auth
    app = firebase_admin.initialize_app(options={'projectId': 'conexiabeta2'}, name=NAMESPACE)
    api_key = re.search(r"apiKey: '([^']+)'", (root.parent/'lib/firebase_options.dart').read_text(encoding='utf-8')).group(1)

    def login(person):
        request = urllib.request.Request(
            'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key='+api_key,
            data=json.dumps({'email': person['email'], 'password': password, 'returnSecureToken': True}).encode(),
            headers={'Content-Type': 'application/json'},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)['idToken']
        except urllib.error.HTTPError as error:
            raise RuntimeError('Não foi possível validar o login de QA; nenhuma senha existente foi redefinida.') from None

    existing = {}
    for role, person in PEOPLE.items():
        for lookup, value in ((auth.get_user, person['uid']), (auth.get_user_by_email, person['email'])):
            try:
                user = lookup(value, app=app)
            except auth.UserNotFoundError:
                continue
            if user.uid != person['uid'] or user.email != person['email'] or (user.custom_claims or {}).get('qa_fixture') != NAMESPACE:
                raise SystemExit('Conflito de identidade. Nenhuma conta existente será substituída.')
            existing[role] = user
        if role in existing:
            login(person)
    with sqlite3.connect(database) as db:
        for person in PEOPLE.values():
            row = db.execute('SELECT f.uid FROM users u LEFT JOIN firebase_identities f ON f.user=u.id WHERE u.email=?', (person['email'],)).fetchone()
            if row and row[0] != person['uid']:
                raise SystemExit('Conflito de conta local. Nenhum cadastro será substituído.')
    backup = Path.home()/'Documents/Conexia-backups'/f'linked-pair-{time.time_ns()}.sqlite3'
    backup.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as source, sqlite3.connect(backup) as target:
        source.backup(target)
    for role, person in PEOPLE.items():
        if role not in existing:
            auth.create_user(uid=person['uid'], email=person['email'], password=password,
                             display_name=person.get('nickname', person['name']), email_verified=True, app=app)
            auth.set_custom_user_claims(person['uid'], {'qa_fixture': NAMESPACE}, app=app)
    tokens = {role: login(person) for role, person in PEOPLE.items()}
    repo = Repository(str(database))
    try:
        api = Service(repo, development=True, firebase=FirebaseIdentity('conexiabeta2'))
        g, c = PEOPLE['guardian'], PEOPLE['child']
        api.dispatch('POST', '/auth/firebase', {'name': g['name'], 'birth': g['birth']}, tokens['guardian'])
        result = api.dispatch('POST', '/guardian/children', {
            'childToken': tokens['child'], 'name': c['name'], 'birth': c['birth'], 'consent': True,
        }, tokens['guardian'])
        child_id = result['user']['id']
        for role, name in [('guardian',g['name']), ('child',c['nickname'])]:
            api.dispatch('PATCH', '/me', {'name': name, 'private': True, 'messages': True}, tokens[role])
        guardian = api.dispatch('GET', '/me', {}, tokens['guardian'])
        child = api.dispatch('GET', '/me', {}, tokens['child'])
        request = api.dispatch('POST', '/contacts', {'target': guardian['id']}, tokens['child'])
        if request['status'] != 'approved':
            api.dispatch('POST', '/contacts/approve', {'target': child_id}, tokens['guardian'])
            api.dispatch('PATCH', f'/guardian/children/{child_id}/contacts/{request["requestId"]}', {'approved': True}, tokens['guardian'])
        children = api.dispatch('GET', '/guardian/children', {}, tokens['guardian'])['items']
        assert any(v['id'] == child_id for v in children)
        assert child['verified'] and child['approved'] and child['needsGuardian'] and not child['needsNickname']
        assert api.contact(child_id, guardian['id']) and api.contact(guardian['id'], child_id)
        api.dispatch('GET', '/posts', {}, tokens['child'])
        api.dispatch('GET', '/messages/'+guardian['id'], {}, tokens['child'])
        assert not repo.rows('PRAGMA foreign_key_check')
        output = Path.home()/'Downloads/Conexia-acessos-dupla-vinculada.json'
        output.write_text(json.dumps({
            'project': 'conexiabeta2', 'namespace': NAMESPACE,
            'notice': 'Contas fictícias de QA. Confirmação de e-mail e autorização familiar simuladas exclusivamente para testes.',
            'guardian': dict(g, password=password, local_id=guardian['id']),
            'child': dict(c, password=password, local_id=child_id),
            'validated': {'firebaseLogin': True, 'familyLink': True, 'childFeedAccess': True, 'approvedContact': True, 'chatAccess': True},
        }, ensure_ascii=False, indent=2), encoding='utf-8')
        print('Dupla criada/vinculada. Login Firebase, vínculo familiar, acesso ao feed e contato para chat validados.')
        print('Acessos salvos fora do Git: '+str(output))
    finally:
        repo.db.close()


if __name__ == '__main__':
    main()
