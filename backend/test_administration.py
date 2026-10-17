import unittest
from repository import Repository
from service import Service
from security import ApiError, password_hash


class AdministrationTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repository(':memory:')
        self.addCleanup(self.repo.db.close)
        self.service = Service(self.repo, development=True)
        for uid, birth in [('admin','1990-01-01'),('user','2000-01-01'),('child','2012-01-01')]:
            self.repo.execute('INSERT INTO users(id,email,password,name,birth,verified) VALUES(?,?,?,?,?,1)', (uid,uid+'@example.com',password_hash('test password longer'),uid,birth))
        self.repo.execute('INSERT INTO administrators VALUES(?)', ('admin',))
        self.admin = self.service.session(self.repo.one('SELECT * FROM users WHERE id=?', ('admin',)))['accessToken']
        self.user = self.service.session(self.repo.one('SELECT * FROM users WHERE id=?', ('user',)))['accessToken']
        self.child = self.service.session(self.repo.one('SELECT * FROM users WHERE id=?', ('child',)))['accessToken']

    def call(self, method, path, data=None, bearer=None):
        return self.service.dispatch(method,path,data or {},self.admin if bearer is None else bearer,ip='admin-test')

    def denied(self, status, operation):
        with self.assertRaises(ApiError) as caught: operation()
        self.assertEqual(status,caught.exception.status)

    def report(self, target='p'):
        if target == 'p':
            self.repo.execute('INSERT INTO posts VALUES(?,?,?,?,?,?,?)', ('p','user','reported',None,0,1,None))
        self.repo.execute("INSERT INTO reports(id,user,target,reason,created) VALUES('r','user',?,'test reason',1)", (target,))

    def test_roles_server_side_and_private(self):
        self.assertTrue(self.call('GET','/me')['isAdmin'])
        self.assertFalse(self.call('GET','/me',bearer=self.user)['isAdmin'])
        self.denied(403,lambda:self.call('GET','/admin/summary',bearer=self.user))
        self.denied(403,lambda:self.call('PATCH','/admin/reports/r',{'action':'remove'},self.user))
        self.denied(401,lambda:self.call('GET','/admin/summary',bearer=''))
        self.call('PATCH','/me',{'name':'user','isAdmin':True},self.user)
        self.denied(403,lambda:self.call('GET','/admin/reports',bearer=self.user))

    def test_role_does_not_bypass_adult_or_verification_or_development(self):
        self.repo.execute('UPDATE users SET verified=0 WHERE id=?', ('admin',))
        self.denied(403,lambda:self.call('GET','/admin/summary'))
        self.repo.execute('UPDATE users SET verified=1 WHERE id=?', ('admin',))
        self.service.development=False
        # Development session tokens are never accepted by production mode.
        self.denied(401,lambda:self.call('GET','/admin/summary'))
        self.denied(401,lambda:self.call('GET','/me'))
        self.service.development=True
        self.repo.execute('INSERT INTO administrators VALUES(?)', ('child',))
        self.repo.execute("INSERT INTO guardian_links VALUES('child','admin','fictitious',1,'active',1)")
        self.denied(403,lambda:self.call('GET','/admin/summary',bearer=self.child))

    def test_removal_audited_notified_and_cannot_repeat(self):
        self.report()
        self.assertEqual(1,self.call('GET','/admin/summary')['pendingReports'])
        row=self.call('GET','/admin/reports')['items'][0]
        self.assertEqual('reported',row['content'])
        self.assertNotIn('email',row)
        self.call('PATCH','/admin/reports/r',{'action':'remove'})
        self.assertIsNone(self.repo.one("SELECT id FROM posts WHERE id='p'"))
        self.assertEqual('removed',self.repo.one("SELECT status FROM reports WHERE id='r'")['status'])
        self.assertEqual(1,len(self.repo.rows('SELECT * FROM notifications')))
        self.assertEqual(1,len(self.repo.rows("SELECT * FROM audit WHERE event='moderation.remove'")))
        self.denied(409,lambda:self.call('PATCH','/admin/reports/r',{'action':'dismiss'}))

    def test_other_targets_never_delete_accounts_or_messages(self):
        self.report('user')
        self.denied(400,lambda:self.call('PATCH','/admin/reports/r',{'action':'remove'}))
        self.assertEqual('pending',self.repo.one("SELECT status FROM reports WHERE id='r'")['status'])
        self.assertIsNotNone(self.repo.one("SELECT id FROM users WHERE id='user'"))
        self.call('PATCH','/admin/reports/r',{'action':'dismiss'})
        self.assertEqual('dismissed',self.repo.one("SELECT status FROM reports WHERE id='r'")['status'])

    def test_revocation_immediate_and_comment_removal(self):
        self.report()
        self.repo.execute("INSERT INTO comments(id,user,post,text,created) VALUES('c','user','p','comment',1)")
        self.repo.execute("UPDATE reports SET target='c' WHERE id='r'")
        self.call('PATCH','/admin/reports/r',{'action':'remove'})
        self.assertIsNotNone(self.repo.one("SELECT id FROM posts WHERE id='p'"))
        self.assertIsNone(self.repo.one("SELECT id FROM comments WHERE id='c'"))
        self.repo.execute("DELETE FROM administrators WHERE user='admin'")
        self.denied(403,lambda:self.call('GET','/admin/summary'))


if __name__ == '__main__':
    unittest.main()
