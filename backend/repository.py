import sqlite3
from contextlib import contextmanager
from threading import RLock

class Repository:
    """SQLite adapter; services consume this interface, not a global database."""
    def __init__(self, path):
        self.lock = RLock()
        self._depth = 0
        self.db = sqlite3.connect(path, check_same_thread=False, timeout=5)
        self.db.row_factory = sqlite3.Row
        if self.db.execute('PRAGMA user_version').fetchone()[0]>1:
            self.db.close()
            raise ValueError('Database schema is newer than this application')
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.execute('PRAGMA busy_timeout=5000')
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')
        self.db.executescript('''BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,email TEXT UNIQUE NOT NULL,password TEXT NOT NULL,name TEXT NOT NULL,birth TEXT NOT NULL,guardian TEXT,verified INTEGER DEFAULT 0,approved INTEGER DEFAULT 0,bio TEXT DEFAULT '',private INTEGER DEFAULT 1,messages INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS firebase_identities(uid TEXT PRIMARY KEY,user TEXT UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS school_privacy(child TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,mode TEXT NOT NULL CHECK(mode IN ('guardian_only','shared','paused')),updated REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS tutor_links(id TEXT PRIMARY KEY,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,tutor TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,scope TEXT NOT NULL CHECK(scope IN ('summary','history')),state TEXT NOT NULL CHECK(state IN ('pending','active','declined','revoked','expired')),consent_version TEXT NOT NULL,created REAL NOT NULL,expires REAL NOT NULL,updated REAL NOT NULL);
        CREATE UNIQUE INDEX IF NOT EXISTS tutor_live_pair ON tutor_links(child,tutor) WHERE state IN ('pending','active');
        CREATE INDEX IF NOT EXISTS tutor_inbox ON tutor_links(tutor,state,created);
        CREATE TABLE IF NOT EXISTS school_audit(id TEXT PRIMARY KEY,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,actor TEXT REFERENCES users(id) ON DELETE SET NULL,event TEXT NOT NULL,created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS administrators(user TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS review_consents(child TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,granted INTEGER NOT NULL,version TEXT NOT NULL,updated REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS review_consent_events(id TEXT PRIMARY KEY,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,granted INTEGER NOT NULL,version TEXT NOT NULL,created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS enrollment_reviews(id TEXT PRIMARY KEY,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,version TEXT NOT NULL,state TEXT NOT NULL,reason TEXT NOT NULL,created REAL NOT NULL,updated REAL NOT NULL,reviewer TEXT REFERENCES users(id) ON DELETE SET NULL);
        CREATE INDEX IF NOT EXISTS enrollment_reviews_child ON enrollment_reviews(child,created DESC,id DESC);
        CREATE TABLE IF NOT EXISTS review_photos(review TEXT PRIMARY KEY REFERENCES enrollment_reviews(id) ON DELETE CASCADE,cipher BLOB NOT NULL,expires REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS review_events(id TEXT PRIMARY KEY,review TEXT NOT NULL REFERENCES enrollment_reviews(id) ON DELETE CASCADE,actor TEXT REFERENCES users(id) ON DELETE SET NULL,action TEXT NOT NULL,reason TEXT NOT NULL,created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS review_tickets(id TEXT PRIMARY KEY,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,created REAL NOT NULL,expires REAL NOT NULL,state TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS review_limits(user TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,reset REAL NOT NULL,count INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS vision_consents(child TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,granted INTEGER NOT NULL,version TEXT NOT NULL,updated REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS vision_sessions(id TEXT PRIMARY KEY,user TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,version TEXT NOT NULL,challenge TEXT NOT NULL,state TEXT NOT NULL,created REAL NOT NULL,expires REAL NOT NULL,result TEXT);
        CREATE INDEX IF NOT EXISTS vision_sessions_owner ON vision_sessions(user,created);
        CREATE TABLE IF NOT EXISTS vision_limits(user TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,reset REAL NOT NULL,count INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS account_status(user TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,status TEXT NOT NULL CHECK(status IN ('active','suspended')),reason TEXT NOT NULL DEFAULT '',updated REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS account_moderation(id TEXT PRIMARY KEY,actor TEXT REFERENCES users(id) ON DELETE SET NULL,target TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,status TEXT NOT NULL CHECK(status IN ('active','suspended')),reason TEXT NOT NULL,created REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS account_moderation_target ON account_moderation(target,created DESC);
        CREATE TABLE IF NOT EXISTS seed_runs(namespace TEXT PRIMARY KEY,created REAL NOT NULL,manifest TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions(access TEXT PRIMARY KEY,refresh TEXT UNIQUE,user TEXT REFERENCES users(id) ON DELETE CASCADE,expires REAL,refresh_expires REAL);
        CREATE TABLE IF NOT EXISTS challenges(token TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,kind TEXT,expires REAL);
        CREATE TABLE IF NOT EXISTS posts(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,text TEXT,media TEXT,story INTEGER DEFAULT 0,created REAL,expires REAL);
        CREATE TABLE IF NOT EXISTS likes(user TEXT REFERENCES users(id) ON DELETE CASCADE,post TEXT REFERENCES posts(id) ON DELETE CASCADE,PRIMARY KEY(user,post));
        CREATE TABLE IF NOT EXISTS comments(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,post TEXT REFERENCES posts(id) ON DELETE CASCADE,text TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS blocks(user TEXT REFERENCES users(id) ON DELETE CASCADE,target TEXT REFERENCES users(id) ON DELETE CASCADE,PRIMARY KEY(user,target));
        CREATE TABLE IF NOT EXISTS contacts(user TEXT REFERENCES users(id) ON DELETE CASCADE,target TEXT REFERENCES users(id) ON DELETE CASCADE,approved INTEGER DEFAULT 0,PRIMARY KEY(user,target));
        CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,sender TEXT REFERENCES users(id) ON DELETE CASCADE,recipient TEXT REFERENCES users(id) ON DELETE CASCADE,text TEXT,created REAL,read INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,target TEXT,reason TEXT,created REAL,status TEXT DEFAULT 'pending');
        CREATE TABLE IF NOT EXISTS report_decisions(report TEXT PRIMARY KEY REFERENCES reports(id) ON DELETE CASCADE,actor TEXT REFERENCES users(id) ON DELETE SET NULL,action TEXT NOT NULL CHECK(action IN ('dismiss','remove')),reason TEXT NOT NULL,created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS report_context(report TEXT PRIMARY KEY REFERENCES reports(id) ON DELETE CASCADE,category TEXT NOT NULL,priority INTEGER NOT NULL,target_type TEXT NOT NULL,evidence TEXT);
        CREATE INDEX IF NOT EXISTS report_context_priority ON report_context(priority DESC);
        CREATE TABLE IF NOT EXISTS notifications(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,text TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS media(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,mime TEXT,data BLOB);
        CREATE TABLE IF NOT EXISTS media_objects(media TEXT PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,bucket TEXT NOT NULL,object_key TEXT NOT NULL,generation TEXT NOT NULL,bytes INTEGER NOT NULL,sha256 TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS media_transfers(media TEXT PRIMARY KEY,bucket TEXT NOT NULL,object_key TEXT NOT NULL,created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS media_uploads(media TEXT PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS media_deletions(bucket TEXT NOT NULL,object_key TEXT NOT NULL,generation TEXT NOT NULL,created REAL NOT NULL,PRIMARY KEY(bucket,object_key,generation));
        CREATE TRIGGER IF NOT EXISTS queue_cloud_media_delete BEFORE DELETE ON media_objects BEGIN INSERT OR IGNORE INTO media_deletions VALUES(OLD.bucket,OLD.object_key,OLD.generation,strftime('%s','now')); END;
        CREATE VIEW IF NOT EXISTS media_inventory AS SELECT m.id,m.user,m.mime,coalesce(o.bytes,length(m.data),0) bytes FROM media m LEFT JOIN media_objects o ON o.media=m.id;
        CREATE TABLE IF NOT EXISTS post_media(post TEXT REFERENCES posts(id) ON DELETE CASCADE,media TEXT REFERENCES media(id) ON DELETE CASCADE,position INTEGER NOT NULL,PRIMARY KEY(post,position));
        CREATE TABLE IF NOT EXISTS guardian_links(child TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,child_name TEXT NOT NULL,nickname_selected INTEGER DEFAULT 0,state TEXT NOT NULL DEFAULT 'active',created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS profile_media(user TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,media TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS post_categories(post TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,category TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS feed_views(id TEXT PRIMARY KEY,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,post TEXT REFERENCES posts(id) ON DELETE SET NULL,post_key TEXT NOT NULL,category TEXT NOT NULL,day TEXT NOT NULL,first_seen REAL NOT NULL,last_seen REAL NOT NULL,UNIQUE(child,post_key,day));
        CREATE TABLE IF NOT EXISTS family_discussions(id TEXT PRIMARY KEY,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,post TEXT REFERENCES posts(id) ON DELETE SET NULL,creator TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,state TEXT NOT NULL DEFAULT 'open',created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS audit(id TEXT PRIMARY KEY,event TEXT,actor TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS contact_requests(id TEXT PRIMARY KEY,source TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,target TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,accepted INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'pending',created REAL NOT NULL,expires REAL NOT NULL,CHECK(source!=target));
        CREATE TABLE IF NOT EXISTS contact_consents(request TEXT NOT NULL REFERENCES contact_requests(id) ON DELETE CASCADE,child TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,guardian TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,approved INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(request,child));
        CREATE TABLE IF NOT EXISTS mutation_receipts(actor TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,key TEXT NOT NULL,fingerprint TEXT NOT NULL,response TEXT NOT NULL,expires REAL NOT NULL,PRIMARY KEY(actor,key));
        CREATE TABLE IF NOT EXISTS media_created(media TEXT PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,created REAL NOT NULL);
        CREATE TRIGGER IF NOT EXISTS media_timestamp AFTER INSERT ON media BEGIN INSERT INTO media_created VALUES(NEW.id,strftime('%s','now')); END;
        CREATE TABLE IF NOT EXISTS identity_deletions(uid TEXT PRIMARY KEY,created REAL NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_attempt REAL NOT NULL DEFAULT 0,completed REAL);
        CREATE UNIQUE INDEX IF NOT EXISTS contact_request_pending ON contact_requests(source,target) WHERE status='pending';
        CREATE INDEX IF NOT EXISTS contact_consent_guardian ON contact_consents(guardian,child,request);
        CREATE INDEX IF NOT EXISTS contact_requests_pair_status ON contact_requests(source,target,status);
        CREATE INDEX IF NOT EXISTS contact_requests_target_status ON contact_requests(target,status,created DESC);
        CREATE INDEX IF NOT EXISTS mutation_receipts_expiry ON mutation_receipts(expires);
        CREATE INDEX IF NOT EXISTS notifications_user_created ON notifications(user,created DESC);
        CREATE INDEX IF NOT EXISTS feed_views_child_seen ON feed_views(child,last_seen DESC);
        CREATE INDEX IF NOT EXISTS post_media_media ON post_media(media,post);
        CREATE INDEX IF NOT EXISTS posts_feed_cursor ON posts(story,created DESC,id DESC);
        CREATE INDEX IF NOT EXISTS posts_author_cursor ON posts(user,story,created DESC,id DESC);
        CREATE INDEX IF NOT EXISTS messages_pair_cursor ON messages(sender,recipient,created DESC,id DESC);
        CREATE INDEX IF NOT EXISTS contacts_incoming ON contacts(target,approved,user);
        CREATE INDEX IF NOT EXISTS blocks_target ON blocks(target,user);
        CREATE INDEX IF NOT EXISTS likes_post ON likes(post,user);
        COMMIT;
        ''')
        self.db.commit()
        self.db.execute('PRAGMA user_version=1')
        self.db.execute("INSERT OR IGNORE INTO media_created SELECT id,strftime('%s','now') FROM media")
        self.db.commit()
        # Preserve pending invitations from older databases without accepting them.
        self.db.execute("""INSERT INTO contact_requests(id,source,target,created,expires)
            SELECT lower(hex(randomblob(32))),c.user,c.target,strftime('%s','now'),strftime('%s','now')+604800
            FROM contacts c WHERE c.approved=0 AND NOT EXISTS(
                SELECT 1 FROM contact_requests q WHERE q.source=c.user AND q.target=c.target)""")
        self.db.commit()
        # Historical child connections without recorded consent must be requested again.
        self.db.execute("""DELETE FROM contacts AS c WHERE c.approved=1 AND EXISTS(
            SELECT 1 FROM users u WHERE u.id IN (c.user,c.target) AND u.birth>date('now','-18 years'))
            AND NOT EXISTS(SELECT 1 FROM contact_requests q WHERE q.status='approved' AND q.accepted=1
                AND ((q.source=c.user AND q.target=c.target) OR (q.source=c.target AND q.target=c.user))
                AND NOT EXISTS(SELECT 1 FROM users child WHERE child.id IN(c.user,c.target)
                    AND child.birth>date('now','-18 years') AND NOT EXISTS(
                        SELECT 1 FROM contact_consents consent JOIN guardian_links link ON link.child=consent.child
                        WHERE consent.request=q.id AND consent.child=child.id AND consent.guardian=link.guardian AND consent.approved=1)))""")
        self.db.commit()
    def rows(self, sql, args=()):
        with self.lock:
            return [dict(r) for r in self.db.execute(sql, args).fetchall()]
    def one(self, sql, args=()):
        rows = self.rows(sql, args)
        return rows[0] if rows else None
    def execute(self, sql, args=()):
        with self.lock:
            self.db.execute(sql, args)
            if not self._depth:
                self.db.commit()

    @contextmanager
    def transaction(self):
        """Nested units use savepoints; helpers never commit their caller's work."""
        with self.lock:
            depth = self._depth
            savepoint = 'unit_' + str(depth)
            self.db.execute('BEGIN IMMEDIATE' if not depth else 'SAVEPOINT ' + savepoint)
            self._depth += 1
            try:
                yield
                if depth:
                    self.db.execute('RELEASE SAVEPOINT ' + savepoint)
                else:
                    self.db.commit()
            except BaseException:
                if depth:
                    self.db.execute('ROLLBACK TO SAVEPOINT ' + savepoint)
                    self.db.execute('RELEASE SAVEPOINT ' + savepoint)
                else:
                    self.db.rollback()
                raise
            finally:
                self._depth = depth
