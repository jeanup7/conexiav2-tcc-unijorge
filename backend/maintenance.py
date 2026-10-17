"""Run daily before serving to purge expired content and orphaned media."""
import os
import time
from pathlib import Path
from repository import Repository

def purge(repo, orphan_grace_seconds=86400):
    now=time.time()
    repo.execute('DELETE FROM feed_views WHERE last_seen<?',(now-30*86400,))
    repo.execute('DELETE FROM posts WHERE expires IS NOT NULL AND expires <= ?', (now,))
    repo.execute('DELETE FROM challenges WHERE expires <= ?', (now,))
    repo.execute('DELETE FROM sessions WHERE refresh_expires <= ?', (now,))
    # A grace period protects uploads between selecting photos and publishing.
    repo.execute('DELETE FROM media WHERE id IN (SELECT media FROM media_created WHERE created<=?) AND NOT EXISTS(SELECT 1 FROM posts WHERE posts.media=media.id) AND NOT EXISTS(SELECT 1 FROM post_media WHERE post_media.media=media.id) AND NOT EXISTS(SELECT 1 FROM profile_media WHERE profile_media.media=media.id)',(now-orphan_grace_seconds,))
    repo.execute('DELETE FROM mutation_receipts WHERE expires<=?',(now,))
    repo.execute("UPDATE contact_requests SET status='expired' WHERE status='pending' AND expires<=?",(now,))
    # Audit is pseudonymous; this development retention policy needs legal validation.
    repo.execute('DELETE FROM audit WHERE created < ?', (now-30*86400,))

if __name__=='__main__':
    repo=Repository(os.environ.get('DATABASE_PATH',str(Path(__file__).parent/'conexia.sqlite3')))
    purge(repo)
    repo.db.close()
    print('Expired content and unreferenced media removed. Run with API stopped.')
