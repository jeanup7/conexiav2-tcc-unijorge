"""Run daily before serving to purge expired content and orphaned media."""
import os
import time
from pathlib import Path
from repository import Repository

def purge(repo):
    now=time.time()
    repo.execute('DELETE FROM posts WHERE expires IS NOT NULL AND expires <= ?', (now,))
    repo.execute('DELETE FROM challenges WHERE expires <= ?', (now,))
    repo.execute('DELETE FROM sessions WHERE refresh_expires <= ?', (now,))
    # Media cleanup must run offline: concurrent uploads could be not yet attached.
    repo.execute('DELETE FROM media WHERE NOT EXISTS(SELECT 1 FROM posts WHERE posts.media=media.id)')
    # Audit is pseudonymous; this development retention policy needs legal validation.
    repo.execute('DELETE FROM audit WHERE created < ?', (now-30*86400,))

if __name__=='__main__':
    repo=Repository(os.environ.get('DATABASE_PATH',str(Path(__file__).parent/'conexia.sqlite3')))
    purge(repo)
    repo.db.close()
    print('Expired content and unreferenced media removed. Run with API stopped.')
