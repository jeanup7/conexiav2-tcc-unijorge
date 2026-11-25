"""Fresh demo identities and SQLite, exclusively for the local Auth Emulator."""
import argparse
import json
import os
import time
from pathlib import Path
from uuid import uuid4
from firebase_identity import FirebaseIdentity, validate_emulator_environment
from repository import Repository
from security import password_hash, token

def prepare(directory, port):
    project=os.environ.get('FIREBASE_PROJECT_ID','')
    if not validate_emulator_environment(project):raise ValueError('Auth Emulator required')
    directory=Path(directory).resolve()
    database=directory/'test.sqlite3'
    if database.exists():raise ValueError('Use a fresh database')
    directory.mkdir(parents=True,exist_ok=True)
    identity=FirebaseIdentity(project)
    repo=Repository(str(database))
    suffix=uuid4().hex[:12]
    password='Conexia-Local-Only!2026'
    defines={'API_URL':f'http://127.0.0.1:{port}','QA_ISOLATED_DATABASE':True,
             'QA_AUTH_EMULATOR':True,'QA_PASSWORD':password,'QA_PROJECT_ID':project}
    try:
        for role in ['admin','tutor']:
            mail=f'{role}.{suffix}@example.test'
            user=identity.auth.create_user(email=mail,password=password,email_verified=True,app=identity.app)
            uid=token()
            repo.execute('INSERT INTO users(id,email,password,name,birth,verified,private) VALUES(?,?,?,?,?,1,0)',
                         (uid,mail,password_hash(token()),'Admin QA' if role=='admin' else 'Tutor QA','1990-01-01'))
            repo.execute('INSERT INTO firebase_identities VALUES(?,?)',(user.uid,uid))
            if role=='admin':repo.execute('INSERT INTO administrators VALUES(?)',(uid,))
            if role=='tutor':
                pid=token()
                repo.execute('INSERT INTO posts VALUES(?,?,?,?,0,?,NULL)',(pid,uid,'Publicação fictícia para validar a moderação',None,time.time()))
                repo.execute('INSERT INTO post_categories VALUES(?,?)',(pid,'education'))
                defines['QA_REFERENCE_POST']=pid
            defines['QA_'+role.upper()+'_EMAIL']=mail
        defines['QA_GUARDIAN_EMAIL']=f'parent.{suffix}@example.test'
        defines['QA_CHILD_EMAIL']=f'child.{suffix}@example.test'
        (directory/'qa-defines.json').write_text(json.dumps(defines,indent=2),encoding='utf-8')
    finally:repo.db.close()

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',required=True)
    parser.add_argument('--port',type=int,default=8083)
    args=parser.parse_args()
    prepare(args.directory,args.port)
