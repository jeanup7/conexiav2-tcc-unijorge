"""Explicit local operator tool. Run only on a secured backend host, never in Flutter."""
import argparse
import json
import os
from pathlib import Path
from repository import Repository
from security import token
import time

parser=argparse.ArgumentParser(description='Conexia local moderation queue')
parser.add_argument('action',choices=['list','dismiss','remove'])
parser.add_argument('--report')
args=parser.parse_args()
repo=Repository(os.environ.get('DATABASE_PATH',str(Path(__file__).parent/'conexia.sqlite3')))
if args.action=='list':
    print(json.dumps(repo.rows("SELECT id,target,reason,created FROM reports WHERE status='pending' ORDER BY created"),ensure_ascii=False,indent=2))
else:
    if not args.report: parser.error('--report is required')
    report=repo.one('SELECT * FROM reports WHERE id=?',(args.report,))
    if not report: raise SystemExit('Report not found')
    if args.action=='remove':
        post=repo.one('SELECT id FROM posts WHERE id=?',(report['target'],))
        comment=repo.one('SELECT id FROM comments WHERE id=?',(report['target'],))
        if not post and not comment: raise SystemExit('This target needs manual investigation; no content was removed.')
        repo.execute('DELETE FROM posts WHERE id=?',(report['target'],))
        repo.execute('DELETE FROM comments WHERE id=?',(report['target'],))
    repo.execute('UPDATE reports SET status=? WHERE id=?',('removed' if args.action=='remove' else 'dismissed',args.report))
    repo.execute('INSERT INTO notifications VALUES(?,?,?,?)',(token(),report['user'],'Sua denúncia recebeu uma atualização.',time.time()))
    print('Moderation decision recorded. Operator access is controlled by OS access to this host/database.')
repo.db.close()
