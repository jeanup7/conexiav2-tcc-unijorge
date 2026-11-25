"""Dry-run by default. Upload a bounded batch only with --apply and a verified backup."""
import argparse
import os
import sqlite3
import time
from pathlib import Path
from urllib.parse import quote
from backup import backup


def inventory(path,limit):
    uri='file:'+quote(Path(path).resolve().as_posix(),safe='/:')+'?mode=ro'
    with sqlite3.connect(uri,uri=True) as db:
        return db.execute('SELECT id,length(data) FROM media WHERE data IS NOT NULL ORDER BY id LIMIT ?',(limit,)).fetchall()


def migrate(service,ids):
    for mid in ids:
        service.repo.execute('INSERT OR IGNORE INTO media_uploads SELECT id,? FROM media WHERE id=? AND data IS NOT NULL',(time.time(),mid))
    return service.process_media_jobs(limit=len(ids))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',required=True)
    parser.add_argument('--bucket',default=os.environ.get('CONEXIA_MEDIA_BUCKET'))
    parser.add_argument('--limit',type=int,default=10)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--backup')
    args=parser.parse_args()
    if not 1<=args.limit<=1000:parser.error('Use um lote entre 1 e 1000 imagens.')
    rows=inventory(args.database,args.limit)
    print(f'Lote: {len(rows)} imagens, {sum(size for _,size in rows)} bytes. Os IDs serão preservados.')
    if not args.apply:
        print('Simulação: nenhum dado alterado e nenhuma chamada ao Storage.')
        return
    if not args.bucket or not args.backup:parser.error('--apply exige --bucket e --backup em um destino novo.')
    from firebase_identity import FirebaseIdentity
    from media_storage import FirebaseMediaStorage
    from repository import Repository
    from service import Service
    identity=FirebaseIdentity(os.environ['FIREBASE_PROJECT_ID'])
    storage=FirebaseMediaStorage(identity.app,args.bucket)
    backup(args.database,args.backup)
    repo=Repository(args.database)
    try:
        result=migrate(Service(repo,development=True,media_storage=storage),[mid for mid,_ in rows])
        print('Resultado do lote:',result)
        if result['failed']:raise SystemExit('Transferências pendentes permanecem na fila; as fotos locais foram preservadas.')
    finally:repo.db.close()


if __name__=='__main__':main()
