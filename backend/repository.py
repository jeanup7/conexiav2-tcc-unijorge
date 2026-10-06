import sqlite3

class Repository:
    """SQLite adapter; services consume this interface, not a global database."""
    def __init__(self, path):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,email TEXT UNIQUE NOT NULL,password TEXT NOT NULL,name TEXT NOT NULL,birth TEXT NOT NULL,guardian TEXT,verified INTEGER DEFAULT 0,approved INTEGER DEFAULT 0,bio TEXT DEFAULT '',private INTEGER DEFAULT 1,messages INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS sessions(access TEXT PRIMARY KEY,refresh TEXT UNIQUE,user TEXT REFERENCES users(id) ON DELETE CASCADE,expires REAL,refresh_expires REAL);
        CREATE TABLE IF NOT EXISTS challenges(token TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,kind TEXT,expires REAL);
        CREATE TABLE IF NOT EXISTS posts(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,text TEXT,media TEXT,story INTEGER DEFAULT 0,created REAL,expires REAL);
        CREATE TABLE IF NOT EXISTS likes(user TEXT REFERENCES users(id) ON DELETE CASCADE,post TEXT REFERENCES posts(id) ON DELETE CASCADE,PRIMARY KEY(user,post));
        CREATE TABLE IF NOT EXISTS comments(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,post TEXT REFERENCES posts(id) ON DELETE CASCADE,text TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS blocks(user TEXT REFERENCES users(id) ON DELETE CASCADE,target TEXT REFERENCES users(id) ON DELETE CASCADE,PRIMARY KEY(user,target));
        CREATE TABLE IF NOT EXISTS contacts(user TEXT REFERENCES users(id) ON DELETE CASCADE,target TEXT REFERENCES users(id) ON DELETE CASCADE,approved INTEGER DEFAULT 0,PRIMARY KEY(user,target));
        CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,sender TEXT REFERENCES users(id) ON DELETE CASCADE,recipient TEXT REFERENCES users(id) ON DELETE CASCADE,text TEXT,created REAL,read INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,target TEXT,reason TEXT,created REAL,status TEXT DEFAULT 'pending');
        CREATE TABLE IF NOT EXISTS notifications(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,text TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS media(id TEXT PRIMARY KEY,user TEXT REFERENCES users(id) ON DELETE CASCADE,mime TEXT,data BLOB);
        CREATE TABLE IF NOT EXISTS audit(id TEXT PRIMARY KEY,event TEXT,actor TEXT,created REAL);
        ''')
        self.db.commit()
    def rows(self, sql, args=()):
        return [dict(r) for r in self.db.execute(sql, args).fetchall()]
    def one(self, sql, args=()):
        rows = self.rows(sql, args)
        return rows[0] if rows else None
    def execute(self, sql, args=()):
        self.db.execute(sql, args)
        self.db.commit()
