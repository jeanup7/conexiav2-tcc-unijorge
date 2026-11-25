"""Assign user-supplied pictures to the manual QA profiles; leave post media intact."""
import base64,json,os,sqlite3,time
from pathlib import Path
from images import normalize
from repository import Repository

def main():
 if os.environ.get('CONEXIA_DEV')!='1':raise SystemExit('Use CONEXIA_DEV=1.')
 root=Path(__file__).resolve().parent
 files=[root/'fixtures/seed_media'/n for n in ['zeno_kamau.jpg','ben_ten.jpg','robin.jpg','avatar_ilustrado.jpg','garoto_quadrinhos.jpg','manga_mar.jpg','chapeu_aventura.jpg','luffy_pelucia.jpg','skate.jpg']]+[root.parent/'assets/feed'/n for n in ['luffy.jpg','peter_parker.jpg','shikamaru_bahia.png','spider_man.webp']]
 accounts=[(f'conexia-manual15-v1-{i:02}',files[(i-1)%len(files)]) for i in range(1,16)]
 path=root/'conexia.sqlite3'
 # Resolve minors by stable Firebase UID, without reading credentials.
 with sqlite3.connect(path) as db:
  for slug,asset in [('sofia','garoto_quadrinhos.jpg'),('leo','ben_ten.jpg'),('bia','avatar_ilustrado.jpg')]:
   row=db.execute('SELECT user FROM firebase_identities WHERE uid=?',('conexia-families-qa-v1-'+slug,)).fetchone()
   if not row:raise ValueError('Conta de menor ausente.')
   accounts.append((row[0],root/'fixtures/seed_media'/asset))
  for uid,_ in accounts:
   if not db.execute('SELECT 1 FROM users WHERE id=?',(uid,)).fetchone():raise ValueError('Conta QA ausente.')
 normalized=[]
 for uid,asset in accounts:
  mime={'.jpg':'image/jpeg','.png':'image/png','.webp':'image/webp'}[asset.suffix]
  mime,data=normalize({'mime':mime,'data':base64.b64encode(asset.read_bytes()).decode()})
  normalized.append((uid,asset,mime,data))
 backup=Path.home()/'Documents/Conexia-backups'/f'qa-avatars-{time.time_ns()}.sqlite3'
 backup.parent.mkdir(parents=True,exist_ok=True)
 with sqlite3.connect(path) as src,sqlite3.connect(backup) as dst:src.backup(dst)
 r=Repository(str(path));manifest=[]
 with r.transaction():
  for uid,asset,mime,data in normalized:
   mid='qa-supplied-avatar-'+uid
   # Use separate IDs so posts sharing the old avatar retain their original image.
   r.db.execute('INSERT INTO media VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET mime=excluded.mime,data=excluded.data',(mid,uid,mime,data))
   r.db.execute('INSERT INTO profile_media VALUES(?,?) ON CONFLICT(user) DO UPDATE SET media=excluded.media',(uid,mid))
   name=r.one('SELECT name FROM users WHERE id=?',(uid,))['name']
   manifest.append({'user':uid,'name':name,'source':str(asset.relative_to(root.parent)),'media':mid})
  assert not r.rows('PRAGMA foreign_key_check')
  assert len(manifest)==18
 r.db.close()
 (root/'fixtures/manual_avatar_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
 print('18 avatares atualizados com 13 imagens fornecidas pelo usuário. Posts preservados.')
if __name__=='__main__':main()
