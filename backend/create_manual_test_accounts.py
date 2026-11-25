"""Provision exactly 15 reserved, adult QA logins. Run only against development.
Set QA_PASSWORD, CONEXIA_DEV=1, FIREBASE_PROJECT_ID and GOOGLE_APPLICATION_CREDENTIALS.
Credentials are exported outside Git. Reruns reuse owned identities without resetting passwords.
"""
import base64
import json
import os
from pathlib import Path
import sqlite3
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from images import normalize
from repository import Repository
from security import password_hash, token

PEOPLE = [
 ('Ana Beatriz Almeida','ana.beatriz','women/44','1997-03-12','Leitora apaixonada por fotografia, trilhas e boas conversas.'),
 ('Lucas Henrique Santos','lucas.henrique','men/32','1999-08-21','Estudante de tecnologia. Futebol aos domingos e projetos nas horas livres.'),
 ('Mariana Costa Ribeiro','mariana.costa','women/68','1995-11-05','Professora, curiosa por natureza e fã de histórias em quadrinhos.'),
 ('Gabriel Oliveira Mendes','gabriel.oliveira','men/46','2001-04-17','Aprendendo a programar e registrando a cidade pelo celular.'),
 ('Camila Ferreira Lima','camila.ferreira','women/65','1998-06-30','Arte, cinema e receitas que quase sempre dão certo.'),
 ('Rafael Souza Carvalho','rafael.souza','men/52','1994-09-14','Ciclista de fim de semana. Gosto de ciência e música brasileira.'),
 ('Juliana Martins Rocha','juliana.martins','women/21','1996-12-02','Pedagogia, jardinagem e descobertas compartilhadas.'),
 ('Pedro Augusto Nascimento','pedro.augusto','men/22','2002-02-08','Design e animação. Sempre com um caderno de desenhos por perto.'),
 ('Fernanda Araujo Batista','fernanda.araujo','women/32','1993-07-19','Mãe, leitora e entusiasta de atividades educativas em família.'),
 ('Bruno Vinicius Teixeira','bruno.vinicius','men/75','1998-10-23','Jogos de estratégia, astronomia e café com amigos.'),
 ('Larissa Gomes Pereira','larissa.gomes','women/49','2000-01-26','Estudo biologia e compartilho pequenas descobertas do cotidiano.'),
 ('Diego Rodrigues Alves','diego.rodrigues','men/11','1991-05-09','Pai e apaixonado por esportes. Aprendendo coisas novas todos os dias.'),
 ('Isabela Cristina Duarte','isabela.cristina','women/17','1999-03-04','Música, literatura e fotografia. Colecionando momentos simples.'),
 ('Thiago Matheus Barbosa','thiago.matheus','men/61','1997-08-16','Robótica, basquete e ideias para tornar a escola mais divertida.'),
 ('Vitoria Reis Monteiro','vitoria.reis','women/57','2001-11-28','Desenho digital e educação. Adoro aprender em comunidade.'),
]
NAMESPACE = 'conexia-manual15-v1'

def main():
    if os.environ.get('CONEXIA_DEV') != '1' or os.environ.get('FIREBASE_PROJECT_ID') != 'conexiabeta2':
        raise SystemExit('Use somente o ambiente de desenvolvimento conexiabeta2.')
    password = os.environ['QA_PASSWORD']
    if len(password) < 12:
        raise SystemExit('Use uma senha padrão de teste com pelo menos 12 caracteres.')
    import firebase_admin
    from firebase_admin import auth
    app = firebase_admin.initialize_app(options={'projectId':'conexiabeta2'}, name=NAMESPACE)
    root = Path(__file__).resolve().parent
    database = Path(os.environ.get('DATABASE_PATH', str(root/'conexia.sqlite3')))
    output = Path.home()/'Downloads'/'Conexia-15-acessos-teste.json'
    accounts = [dict(uid=f'{NAMESPACE}-{i:02}',name=n,email=f'{slug}.qa15@example.com',photo_url=f'https://randomuser.me/api/portraits/{photo}.jpg',birth=b,bio=bio) for i,(n,slug,photo,b,bio) in enumerate(PEOPLE,1)]
    assert len(accounts)==len({a['email'] for a in accounts})==15
    # Back up before repository initialization/migrations.
    backup = Path.home()/'Documents'/'Conexia-backups'/f'qa15-{time.time_ns()}.sqlite3'
    backup.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as source, sqlite3.connect(backup) as dest:
        source.backup(dest)
    repo = Repository(str(database))
    existing = {}
    for a in accounts:
        for lookup, value in [(auth.get_user,a['uid']),(auth.get_user_by_email,a['email'])]:
            try:
                u = lookup(value,app=app)
            except auth.UserNotFoundError:
                continue
            if u.uid != a['uid'] or u.email != a['email'] or (u.custom_claims or {}).get('qa_fixture') != NAMESPACE:
                raise SystemExit('Identidade existente não pertence a este lote; nenhuma conta será substituída.')
            existing[a['uid']]=u
        local = repo.one('SELECT id FROM users WHERE id=? OR email=?',(a['uid'],a['email']))
        if local and local['id'] != a['uid']:
            raise SystemExit('Conflito de cadastro local.')
    if existing:
        saved = json.loads(output.read_text(encoding='utf-8'))
        if saved['namespace'] != NAMESPACE or any(a['password']!=password for a in saved['accounts']):
            raise SystemExit('Preserve a senha original do lote existente.')
    def photo(a):
        with urllib.request.urlopen(a['photo_url'],timeout=30) as response:
            data=response.read(5*1024*1024+1)
        return normalize({'mime':'image/jpeg','data':base64.b64encode(data).decode()})
    with ThreadPoolExecutor(max_workers=5) as pool:
        photos=list(pool.map(photo,accounts))
    output.write_text(json.dumps({'namespace':NAMESPACE,'project':'conexiabeta2','notice':'Pessoas fictícias; fotos ilustrativas; e-mails reservados sem caixa postal. Confirmação simulada somente para QA.','accounts':[{**a,'password':password} for a in accounts]},ensure_ascii=False,indent=2),encoding='utf-8')
    for a,(mime,data) in zip(accounts,photos):
        if a['uid'] not in existing:
            auth.create_user(uid=a['uid'],email=a['email'],password=password,display_name=a['name'],photo_url=a['photo_url'],email_verified=True,app=app)
            auth.set_custom_user_claims(a['uid'],{'qa_fixture':NAMESPACE},app=app)
        with repo.transaction():
            repo.db.execute('INSERT OR IGNORE INTO users(id,email,password,name,birth,verified,approved,bio,private,messages) VALUES(?,?,?,?,?,1,1,?,0,1)',(a['uid'],a['email'],password_hash(token()),a['name'],a['birth'],a['bio']))
            repo.db.execute('INSERT OR IGNORE INTO firebase_identities VALUES(?,?)',(a['uid'],a['uid']))
            mid=a['uid']+'-avatar'
            repo.db.execute('INSERT OR IGNORE INTO media VALUES(?,?,?,?)',(mid,a['uid'],mime,data))
            repo.db.execute('INSERT OR IGNORE INTO profile_media VALUES(?,?)',(a['uid'],mid))
        print('Preparado: '+a['email'],flush=True)
    assert repo.one('SELECT count(*) AS n FROM users WHERE id LIKE ?',(NAMESPACE+'-%',))['n']==15
    assert not repo.rows('PRAGMA foreign_key_check')
    repo.db.close()
    print('15 contas preparadas. Acessos: '+str(output))

if __name__ == '__main__':
    main()
