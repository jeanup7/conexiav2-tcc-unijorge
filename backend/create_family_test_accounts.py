"""Three fictional Firebase minors, linked through the real guardian service flow.
Development only. QA_PASSWORD and Admin credentials required; credentials stay outside Git.
"""
import base64,json,os,re,sqlite3,time,urllib.request
from pathlib import Path
from repository import Repository
from service import Service
from firebase_identity import FirebaseIdentity
from images import normalize
from seed_manual_interactions import DIALOGUES
BATCH='conexia-families-qa-v1'
SPECS=[
 ('sofia','Sofia Martins Rocha','SofiArte','2016-02-10',7,'garoto_quadrinhos.jpg','Gosto de desenhar, inventar histórias e aprender coisas novas.'),
 ('leo','Leonardo Araujo Batista','LeoExplora','2013-04-18',9,'ben_ten.jpg','Quadrinhos, experiências e jogos de tabuleiro.'),
 ('bia','Beatriz Rodrigues Alves','BiaCriativa','2010-06-22',12,'avatar_ilustrado.jpg','Música, fotografia e projetos criativos com amigos.'),
]
CAPTIONS=[
 ['Inventei uma personagem que conversa com as nuvens. Agora estou desenhando a primeira aventura!','Separei esta imagem para meu mural de personagens favoritos.','Aprendi a fazer uma dobradura hoje. Precisei tentar três vezes, mas consegui.'],
 ['Nosso jogo cooperativo terminou com todo mundo ajudando na última rodada.','Uma inspiração para o próximo desenho de aventura.','Montei uma torre de papel e descobri que dobrar a base faz muita diferença.'],
 ['Estou praticando uma música por partes. Hoje consegui juntar os primeiros trechos.','Referência para um estudo de cores que quero fazer no fim de semana.','Quero montar um pequeno clube de fotografia. Cada semana teria um tema diferente.'],
]
def main():
 if os.environ.get('CONEXIA_DEV')!='1' or os.environ.get('FIREBASE_PROJECT_ID')!='conexiabeta2': raise SystemExit('Use o projeto de desenvolvimento conexiabeta2.')
 password=os.environ['QA_PASSWORD']
 if len(password)<12: raise ValueError('Senha de teste precisa de 12 caracteres.')
 root=Path(__file__).resolve().parent; path=Path(os.environ.get('DATABASE_PATH',str(root/'conexia.sqlite3')))
 if not path.is_file(): raise ValueError('Banco não encontrado.')
 out=Path.home()/'Downloads/Conexia-acessos-familias-teste.json'
 with sqlite3.connect(path) as db:
  if db.execute('SELECT 1 FROM seed_runs WHERE namespace=?',(BATCH,)).fetchone():
   print('Famílias já preparadas; nenhuma duplicação.');return
 saved=json.loads((Path.home()/'Downloads/Conexia-15-acessos-teste.json').read_text(encoding='utf-8'))
 guardian_accounts={a['uid']:a for a in saved['accounts']}
 key=re.search(r"apiKey: '([^']+)'",(root.parent/'lib/firebase_options.dart').read_text()).group(1)
 def login(email,pw):
  request=urllib.request.Request('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key='+key,data=json.dumps({'email':email,'password':pw,'returnSecureToken':True}).encode(),headers={'Content-Type':'application/json'})
  with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)['idToken']
 import firebase_admin
 from firebase_admin import auth
 app=firebase_admin.initialize_app(options={'projectId':'conexiabeta2'},name=BATCH)
 families=[]; previous={}
 if out.exists(): previous={a['child']['uid']:a['child'] for a in json.loads(out.read_text(encoding='utf-8'))['families']}
 for slug,name,nick,birth,g,asset,bio in SPECS:
  uid=BATCH+'-'+slug;email=slug+'.familia.qa@example.com'; guardian=guardian_accounts[f'conexia-manual15-v1-{g:02}']
  for lookup,value in [(auth.get_user,uid),(auth.get_user_by_email,email)]:
   try:u=lookup(value,app=app)
   except auth.UserNotFoundError:continue
   if u.uid!=uid or u.email!=email or (u.custom_claims or {}).get('qa_fixture')!=BATCH:raise ValueError('Identidade não pertence a este lote.')
   if uid not in previous or previous[uid]['password']!=password:raise ValueError('Preserve o arquivo e a senha originais.')
  families.append({'guardian':{k:guardian[k] for k in ('uid','name','email','password')},'child':dict(uid=uid,email=email,name=name,nickname=nick,birth=birth,password=password,asset=asset,bio=bio)})
 # Authenticate guardians before provisioning anything remotely.
 tokens={f['guardian']['uid']:login(f['guardian']['email'],f['guardian']['password']) for f in families}
 out.write_text(json.dumps({'project':'conexiabeta2','namespace':BATCH,'notice':'Famílias fictícias de QA. Verificação de e-mail, consentimentos e atividade simulados.','families':families},ensure_ascii=False,indent=2),encoding='utf-8')
 backup=Path.home()/'Documents/Conexia-backups'/f'families-{time.time_ns()}.sqlite3';backup.parent.mkdir(parents=True,exist_ok=True)
 with sqlite3.connect(path) as src,sqlite3.connect(backup) as dst:src.backup(dst)
 for f in families:
  child=f['child']
  try:auth.get_user(child['uid'],app=app)
  except auth.UserNotFoundError:
   auth.create_user(uid=child['uid'],email=child['email'],password=password,display_name=child['nickname'],email_verified=True,app=app)
   auth.set_custom_user_claims(child['uid'],{'qa_fixture':BATCH},app=app)
  tokens[child['uid']]=login(child['email'],password)
 repo=Repository(str(path));api=Service(repo,development=True,firebase=FirebaseIdentity('conexiabeta2'))
 # Real Firebase tokens are verified when linking each family and selecting nickname.
 for f in families:
  c=f['child'];g=f['guardian']
  result=api.dispatch('POST','/guardian/children',{'childToken':tokens[c['uid']],'name':c['name'],'birth':c['birth'],'consent':True},tokens[g['uid']])
  c['local_id']=result['user']['id']
  api.dispatch('PATCH','/me',{'name':c['nickname'],'bio':c['bio'],'private':True,'messages':True},tokens[c['uid']])
  print('Vinculado e login validado: '+c['email'],flush=True)
 with repo.transaction():
  for i,f in enumerate(families):
   c=f['child'];cid=c['local_id'];mid=BATCH+'-avatar-'+str(i)
   mime,data=normalize({'mime':'image/jpeg','data':base64.b64encode((root/'fixtures/seed_media'/c['asset']).read_bytes()).decode()})
   repo.db.execute('INSERT OR IGNORE INTO media VALUES(?,?,?,?)',(mid,cid,mime,data))
   repo.db.execute('INSERT OR IGNORE INTO profile_media VALUES(?,?)',(cid,mid))
   for j,caption in enumerate(CAPTIONS[i]):
    pid=f'{BATCH}-post-{i}-{j}'
    repo.db.execute('INSERT OR IGNORE INTO posts VALUES(?,?,?,?,0,?,NULL)',(pid,cid,caption,mid if j==1 else None,time.time()-(i+1)*3600-j*86400))
    if j==1:repo.db.execute('INSERT OR IGNORE INTO post_media VALUES(?,?,0)',(pid,mid))
    repo.db.execute('INSERT OR IGNORE INTO post_categories VALUES(?,?)',(pid,['art','education','music'][i]))
  # Own guardian + peer pairs; both minors require independent guardian approval.
  pairs=[(f['child']['local_id'],f['guardian']['uid']) for f in families]+[(families[a]['child']['local_id'],families[b]['child']['local_id']) for a,b in [(0,1),(1,2),(0,2)]]
  for k,(a,b) in enumerate(pairs):
   ua=repo.one('SELECT * FROM users WHERE id=?',(a,));ub=repo.one('SELECT * FROM users WHERE id=?',(b,))
   request=api.contacts.create(ua,b)
   if request['status']!='approved':
    api.contacts.accept(ub,a)
    for child,guardian in api.contacts.required(ua,ub).items():
     api.contacts.decide(repo.one('SELECT * FROM users WHERE id=?',(guardian,)),child,request['requestId'],{'approved':True})
   assert api.contact(a,b) and api.contact(b,a)
   for n,line in enumerate(DIALOGUES[[1,14,17,6,13,18][k]]):
    sender,recipient=(a,b) if n%2==0 else (b,a)
    repo.db.execute('INSERT OR IGNORE INTO messages VALUES(?,?,?,?,?,?)',(f'{BATCH}-chat-{k}-{n}',sender,recipient,line,time.time()-86400*(k+1)+n*120,int(n<10)))
  for i,f in enumerate(families):
   child=repo.one('SELECT * FROM users WHERE id=?',(f['child']['local_id'],));guardian=repo.one('SELECT * FROM users WHERE id=?',(f['guardian']['uid'],))
   for j in range(3):
    pid=f'{BATCH}-post-{(i+1)%3}-{j}'
    repo.db.execute('INSERT OR IGNORE INTO likes VALUES(?,?)',(child['id'],pid))
    repo.db.execute('INSERT OR IGNORE INTO comments VALUES(?,?,?,?,?)',(f'{BATCH}-comment-{i}-{j}',child['id'],pid,['Gostei da ideia! Quero tentar também.','Essa referência combina com seu projeto.','Depois conta como ficou a próxima tentativa!'][j],time.time()-1200+j*60))
    api.supervision.record(child,pid,{'visibleMs':3000})
   api.supervision.discuss(guardian,child['id'],{'post':f'{BATCH}-post-{(i+1)%3}-0'})
  assert not repo.rows('PRAGMA foreign_key_check')
  repo.db.execute('INSERT INTO seed_runs VALUES(?,?,?)',(BATCH,time.time(),json.dumps({'children':[f['child']['local_id'] for f in families],'posts':9,'chats':6,'messages':72,'simulated_family_activity':True})))
 out.write_text(json.dumps({'project':'conexiabeta2','namespace':BATCH,'notice':'Famílias fictícias de QA. Verificação de e-mail, consentimentos e atividade simulados.','families':families},ensure_ascii=False,indent=2),encoding='utf-8')
 repo.db.close()
 print('3 menores vinculados, 9 posts, 6 chats, 72 mensagens, 9 curtidas, 9 comentários e atividade familiar. Acessos: '+str(out))
if __name__=='__main__':main()
