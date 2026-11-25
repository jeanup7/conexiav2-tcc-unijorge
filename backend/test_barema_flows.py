import time
import tempfile
from pathlib import Path
import unittest
from repository import Repository
from service import Service
from security import ApiError
from test_family import FamilyFirebase


class BaremaFlowTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repository(':memory:')
        self.addCleanup(self.repo.db.close)
        self.identity = FamilyFirebase()
        self.api = Service(self.repo, development=True, firebase=self.identity)
        self.parent = self.call('POST','/auth/firebase',{'name':'Parent','birth':'1990-01-01'})['user']['id']
        self.other = self.call('POST','/auth/firebase',{'name':'Other','birth':'1990-01-01'},'other')['user']['id']
        self.body = {'childToken':'child','name':'Private name','birth':'2015-01-01','consent':True}
        self.child = self.call('POST','/guardian/children',self.body)['user']['id']
        self.identity.tokens['child']['email_verified'] = True
        self.call('PATCH','/me',{'name':'Nickname','messages':True},'child')
        self.call('PATCH','/me',{'messages':True},'other')
        rid=self.call('POST','/contacts',{'target':self.other},'child')['requestId']
        self.call('POST','/contacts/approve',{'target':self.child},'other')
        self.call('PATCH',f'/guardian/children/{self.child}/contacts/{rid}',{'approved':True})
        self.call('POST','/messages/'+self.other,{'text':'Approved message'},'child')

    def call(self, method, path, data=None, actor='parent'):
        return self.api.dispatch(method,path,data or {},actor)

    def denied(self, status, action):
        with self.assertRaises(ApiError) as error: action()
        self.assertEqual(status,error.exception.status)

    def test_revoked_contact_disappears_and_does_not_return_after_unblock(self):
        self.assertEqual(self.child,self.call('GET','/conversations',actor='other')['items'][0]['id'])
        self.call('DELETE','/contacts/'+self.other,actor='child')
        self.assertEqual([],self.call('GET','/conversations',actor='other')['items'])
        self.denied(403,lambda:self.call('GET','/messages/'+self.child,actor='other'))
        self.call('POST','/blocks',{'target':self.other},'child')
        self.call('DELETE','/blocks/'+self.other,actor='child')
        self.assertEqual([],self.call('GET','/conversations',actor='child')['items'])

    def test_paused_link_blocks_social_endpoints_and_hides_conversation(self):
        self.call('PATCH','/guardian/children/'+self.child,{'state':'paused'})
        for path in ['/posts','/stories','/profiles','/conversations','/messages/'+self.other]:
            self.denied(403,lambda:self.call('GET',path,actor='child'))
        self.assertEqual([],self.call('GET','/conversations',actor='other')['items'])
        self.call('POST','/guardian/children',self.body)
        self.assertEqual('paused',self.call('GET','/guardian/status',actor='child')['state'])
        self.call('PATCH','/guardian/children/'+self.child,{'state':'active'})
        self.assertEqual(self.child,self.call('GET','/conversations',actor='other')['items'][0]['id'])

    def test_suspended_or_unverified_guardian_removes_child_from_conversations(self):
        self.identity.tokens['parent']['email_verified']=False
        self.assertEqual([],self.call('GET','/conversations',actor='other')['items'])
        self.identity.tokens['parent']['email_verified']=True
        self.repo.execute('INSERT INTO account_status VALUES(?,?,?,?)',(self.parent,'suspended','review',time.time()))
        self.assertEqual([],self.call('GET','/conversations',actor='other')['items'])

    def test_retry_with_different_birth_is_rejected_without_modifying_child(self):
        self.denied(409,lambda:self.call('POST','/guardian/children',dict(self.body,birth='2010-01-01')))
        self.assertEqual('2015-01-01',self.repo.one('SELECT birth FROM users WHERE id=?',(self.child,))['birth'])
        self.assertEqual(self.child,self.call('POST','/guardian/children',self.body)['user']['id'])

    def test_report_decision_is_persistent_and_visible_only_to_reporter(self):
        self.repo.execute('INSERT INTO administrators VALUES(?)',(self.parent,))
        pid=self.call('POST','/posts',{'text':'Reported example'},'child')['id']
        rid=self.call('POST','/reports',{'target':pid,'reason':'Review this','category':'bullying'},'other')['id']
        self.denied(403,lambda:self.call('PATCH','/admin/reports/'+rid,{'action':'remove'},'child'))
        self.call('PATCH','/admin/reports/'+rid,{'action':'remove','reason':'Personal attack removed.'})
        report=self.call('GET','/reports',actor='other')['items'][0]
        self.assertEqual('removed',report['status'])
        self.assertEqual('Personal attack removed.',report['decisionReason'])
        self.assertIsInstance(report['decidedAt'],float)
        self.assertNotIn('actor',report)
        exported=self.call('GET','/me/export',actor='other')['reportDecisions']
        self.assertEqual(rid,exported[0]['report'])
        self.assertNotIn('actor',exported[0])
        self.assertEqual([],self.call('GET','/reports',actor='child')['items'])
        self.denied(409,lambda:self.call('PATCH','/admin/reports/'+rid,{'action':'dismiss'}))
        self.assertEqual(1,len(self.repo.rows('SELECT * FROM report_decisions')))

    def test_additive_migration_preserves_historical_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            path=str(Path(directory)/'legacy.sqlite3')
            old=Repository(path)
            old.execute("INSERT INTO users(id,email,password,name,birth,verified) VALUES('legacy','legacy@example.com','unused','Legacy','1990-01-01',1)")
            old.execute("INSERT INTO reports(id,user,target,reason,created) VALUES('old','legacy','general','Historical report',1)")
            old.execute('DROP TABLE report_decisions')
            old.db.close()
            current=Repository(path)
            try:
                api=Service(current,development=True)
                access=api.session(current.one("SELECT * FROM users WHERE id='legacy'"))['accessToken']
                result=api.dispatch('GET','/reports',{},access)['items'][0]
                self.assertEqual('Historical report',result['reason'])
                self.assertIsNone(result['decisionReason'])
                self.assertEqual('pending',result['status'])
            finally:
                current.db.close()
