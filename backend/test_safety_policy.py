"""Regression checks for report privacy, triage, and moderation enforcement."""
import unittest
from repository import Repository
from service import Service
from security import ApiError


class SafetyPolicyTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repository(':memory:')
        self.addCleanup(self.repo.db.close)
        self.api = Service(self.repo, development=True)
        for uid, birth in [('admin','1990-01-01'),('a','2000-01-01'),('b','2000-01-01'),('child','2012-01-01')]:
            self.repo.execute('INSERT INTO users(id,email,password,name,birth,verified) VALUES(?,?,?,?,?,1)', (uid,uid+'@example.com','unused',uid,birth))
        self.repo.execute("INSERT INTO administrators VALUES('admin')")
        self.repo.execute("INSERT INTO guardian_links VALUES('child','admin','private name',1,'active',1)")
        self.tokens = {uid:self.api.session(self.repo.one('SELECT * FROM users WHERE id=?',(uid,)))['accessToken'] for uid in ('admin','a','b','child')}

    def call(self, method, path, data=None, actor='a'):
        return self.api.dispatch(method,path,data or {},self.tokens[actor],ip='safety-test')

    def denied(self, status, action):
        with self.assertRaises(ApiError) as error: action()
        self.assertEqual(status,error.exception.status)

    def test_imported_public_minor_remains_private(self):
        self.repo.execute("UPDATE users SET private=0 WHERE id='child'")
        self.assertEqual(1,self.call('GET','/me',actor='child')['private'])
        self.denied(404,lambda:self.call('GET','/profiles/child'))
        self.assertFalse(any(p['id']=='child' for p in self.call('GET','/profiles')['items']))

    def test_cannot_report_unseen_private_content_or_unknown_target(self):
        post=self.call('POST','/posts',{'text':'private'},actor='b')['id']
        for target in (post,'unknown'):
            self.denied(404,lambda:self.call('POST','/reports',{'target':target,'reason':'test reason'}))
        self.assertEqual([],self.repo.rows('SELECT * FROM reports'))

    def test_only_message_participants_can_submit_evidence_even_after_block(self):
        self.repo.execute("INSERT INTO messages(id,sender,recipient,text,created) VALUES('msg','a','b','reported message',1)")
        self.call('POST','/blocks',{'target':'b'})
        report=self.call('POST','/reports',{'target':'msg','reason':'unwanted contact','category':'unwanted_contact'})
        self.assertEqual('reported message',self.repo.one('SELECT evidence FROM report_context WHERE report=?',(report['id'],))['evidence'])
        self.denied(404,lambda:self.call('POST','/reports',{'target':'msg','reason':'test reason'},actor='admin'))
        self.assertEqual([],self.call('GET','/reports',actor='b')['items'])

    def test_triage_duplicate_suppression_and_no_accused_notification(self):
        data={'target':'general','reason':'urgent threat','category':'threat'}
        urgent=self.call('POST','/reports',data)
        self.assertEqual(urgent['id'],self.call('POST','/reports',data)['id'])
        self.call('POST','/reports',{'target':'general','reason':'other issue','category':'other'})
        queue=self.call('GET','/admin/reports',actor='admin')['items']
        self.assertEqual(urgent['id'],queue[0]['id'])
        self.assertEqual(3,queue[0]['priority'])
        self.assertNotIn('user',queue[0])
        self.assertEqual([],self.repo.rows('SELECT * FROM notifications'))
        self.denied(400,lambda:self.call('POST','/reports',dict(data,category='invalid')))
        self.denied(400,lambda:self.call('POST','/reports',dict(data,notifyGuardian='true')))

    def test_guardian_support_is_opt_in_and_does_not_leak_content(self):
        self.call('POST','/reports',{'target':'general','reason':'private confidential details','category':'bullying'},actor='child')
        self.assertEqual([],self.repo.rows('SELECT * FROM notifications'))
        self.call('POST','/reports',{'target':'general','reason':'other confidential details','category':'threat','notifyGuardian':True},actor='child')
        notifications=self.call('GET','/notifications',actor='admin')['items']
        self.assertEqual(1,len(notifications))
        self.assertNotIn('confidential',notifications[0]['text'])
        self.assertNotIn('threat',notifications[0]['text'])

    def test_suspension_applies_to_existing_sessions_and_can_be_reversed(self):
        self.denied(403,lambda:self.call('PATCH','/admin/users/b',{'status':'suspended','reason':'test moderation'}))
        self.call('PATCH','/admin/users/a',{'status':'suspended','reason':'test moderation'},actor='admin')
        self.denied(403,lambda:self.call('POST','/posts',{'text':'blocked'}))
        self.assertEqual('suspended',self.call('GET','/me')['accountStatus'])
        self.assertIn('profile',self.call('GET','/me/export'))
        self.call('PATCH','/admin/users/a',{'status':'active','reason':'review accepted'},actor='admin')
        self.call('POST','/posts',{'text':'restored'})
        history=self.call('GET','/me/export')['moderationHistory']
        self.assertEqual(['suspended','active'],[v['status'] for v in history])
        self.assertNotIn('actor',history[0])
        self.denied(403,lambda:self.call('PATCH','/admin/users/admin',{'status':'suspended','reason':'test moderation'},actor='admin'))
        self.assertIsNotNone(self.repo.one("SELECT 1 FROM audit WHERE event='moderation.account.suspended'"))

    def test_evidence_survives_author_deletion_and_export_is_private(self):
        pid=self.call('POST','/posts',{'text':'evidence text'})['id']
        report=self.call('POST','/reports',{'target':pid,'reason':'test reason'})
        self.call('DELETE','/posts/'+pid)
        queue=self.call('GET','/admin/reports',actor='admin')['items']
        self.assertEqual('evidence text',queue[0]['content'])
        self.assertEqual(report['id'],self.call('GET','/me/export')['reportContext'][0]['report'])
        self.assertEqual([],self.call('GET','/me/export',actor='b')['reportContext'])
