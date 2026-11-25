import unittest,time
from repository import Repository
from service import Service
from security import ApiError
class Identity:
    def verify(self,bearer):return {'uid':bearer,'email':bearer+'@example.com','email_verified':True}
    def verified_email(self,uid):return True
class SchoolTests(unittest.TestCase):
    def setUp(self):
        self.r=Repository(':memory:');self.addCleanup(self.r.db.close)
        for uid,birth in [('parent','1980-01-01'),('child','2014-01-01'),('tutor','1990-01-01'),('stranger','1985-01-01')]:
            self.r.execute('INSERT INTO users(id,email,password,name,birth,verified,messages) VALUES(?,?,?,?,?,1,1)',(uid,uid+'@example.com','unused',uid,birth))
            self.r.execute('INSERT INTO firebase_identities VALUES(?,?)',(uid,uid))
        self.r.execute("INSERT INTO guardian_links VALUES('child','parent','Private child name',1,'active',?)",(time.time(),))
        self.s=Service(self.r,development=True,firebase=Identity())
    def call(self,method,path,data=None,who='parent'):return self.s.dispatch(method,path,data or {},who)
    def denied(self,status,fn):
        with self.assertRaises(ApiError) as c:fn()
        self.assertEqual(c.exception.status,status)
    def invite(self,scope='summary'):
        return self.call('POST','/school/children/child/tutors',{'tutorId':'tutor','scope':scope,'consent':True,'consentVersion':'school-v1'})['id']
    def activate(self,scope='summary'):
        rid=self.invite(scope)
        self.call('POST','/school/invitations/'+rid+'/decision',{'accept':True},'tutor')
        self.call('PATCH','/school/children/child/privacy',{'mode':'shared'})
        return rid
    def test_consent_acceptance_default_and_summary(self):
        self.denied(400,lambda:self.call('POST','/school/children/child/tutors',{'tutorId':'tutor'}))
        rid=self.invite();self.assertEqual(self.invite(),rid)
        self.assertEqual(self.call('GET','/school/students',who='tutor')['items'],[])
        self.call('POST','/school/invitations/'+rid+'/decision',{'accept':True},'tutor')
        self.denied(403,lambda:self.call('GET','/school/children/child/activity',who='tutor'))
        self.call('PATCH','/school/children/child/privacy',{'mode':'shared'})
        result=self.call('GET','/school/children/child/activity',who='tutor')
        self.assertNotIn('history',result);self.assertNotIn('email',result['child'])
        self.assertEqual(len(self.call('GET','/school/students',who='tutor')['items']),1)
    def test_revoke_pause_and_scope_upgrade(self):
        rid=self.activate()
        self.denied(409,lambda:self.invite('history'))
        self.call('PATCH','/school/children/child/privacy',{'mode':'paused'})
        self.denied(403,lambda:self.call('GET','/school/children/child/activity',who='tutor'))
        self.call('PATCH','/school/children/child/privacy',{'mode':'shared'})
        self.call('DELETE','/school/children/child/tutors/'+rid)
        self.denied(404,lambda:self.call('GET','/school/children/child/activity',who='tutor'))
        self.denied(409,lambda:self.call('POST','/school/invitations/'+rid+'/decision',{'accept':True},'tutor'))
    def test_invitation_expiry_and_recipient(self):
        rid=self.invite()
        self.denied(404,lambda:self.call('POST','/school/invitations/'+rid+'/decision',{'accept':True},'stranger'))
        self.r.execute('UPDATE tutor_links SET expires=?',(time.time()-1,))
        self.denied(409,lambda:self.call('POST','/school/invitations/'+rid+'/decision',{'accept':True},'tutor'))
        self.assertNotEqual(rid,self.invite())
    def test_family_isolation_and_messages(self):
        self.activate()
        for who in ['stranger','tutor']:
            self.denied(404,lambda:self.call('PATCH','/school/children/child/privacy',{'mode':'shared'},who))
        self.denied(403,lambda:self.call('GET','/messages/child',who='tutor'))
        self.assertEqual(self.call('GET','/school/children/child/privacy',who='child')['mode'],'shared')
        self.denied(404,lambda:self.call('GET','/school/children/child/audit',who='stranger'))
    def test_suspension_family_pause_and_block(self):
        self.activate()
        self.r.execute("UPDATE guardian_links SET state='paused'")
        self.denied(403,lambda:self.call('GET','/school/children/child/activity',who='tutor'))
        self.r.execute("UPDATE guardian_links SET state='active'")
        self.r.execute("INSERT INTO blocks VALUES('child','tutor')")
        self.denied(403,lambda:self.call('GET','/school/children/child/activity',who='tutor'))
        self.r.execute('DELETE FROM blocks')
        self.r.execute("INSERT INTO account_status VALUES('parent','suspended','test',?)",(time.time(),))
        self.denied(403,lambda:self.call('GET','/school/children/child/activity',who='tutor'))
    def test_history_minimization_export_and_delete(self):
        self.activate('history')
        for i,stamp in enumerate([time.time()-86400,time.time()+.01]):
            self.r.execute('INSERT INTO feed_views VALUES(?,?,NULL,?,?,?,?,?)',(str(i),'child','post'+str(i),'art','2026-10-26',stamp,stamp))
        result=self.call('GET','/school/children/child/activity',who='tutor')
        self.assertEqual(result['total'],1)
        self.assertEqual(set(result['history'][0]),{'category','seenAt'})
        self.assertEqual(len(self.call('GET','/me/export',who='child')['schoolLinks']),1)
        self.r.execute("DELETE FROM users WHERE id='child'")
        self.assertEqual(self.r.rows('SELECT * FROM tutor_links'),[])
        self.assertEqual(self.r.rows('PRAGMA foreign_key_check'),[])
if __name__=='__main__':unittest.main()
