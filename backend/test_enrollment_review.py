import base64
from io import BytesIO
import time
import unittest
from cryptography.fernet import Fernet
from PIL import Image
from repository import Repository
from service import Service
from security import ApiError
from test_family import FamilyFirebase
from enrollment_review import ReviewVault,VERSION

class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.r=Repository(':memory:');self.addCleanup(self.r.db.close)
        self.identity=FamilyFirebase()
        self.s=Service(self.r,development=True,firebase=self.identity,review_required=True,review_vault=ReviewVault(Fernet.generate_key()))
        self.parent=self.call('POST','/auth/firebase',{'name':'Parent','birth':'1990-01-01'})['user']['id']
        self.admin=self.call('POST','/auth/firebase',{'name':'Reviewer','birth':'1990-01-01'},'other')['user']['id']
        self.r.execute('INSERT INTO administrators VALUES(?)',(self.admin,))
        self.child=self.call('POST','/guardian/children',{'childToken':'child','name':'Private name','birth':'2014-01-01','consent':True})['user']['id']
        self.identity.tokens['child']['email_verified']=True
        self.call('PATCH','/me',{'name':'Child nickname'},'child')
        output=BytesIO();Image.new('RGB',(320,320),'blue').save(output,format='JPEG')
        self.photo=output.getvalue()
    def call(self,method,path,data=None,who='parent'):return self.s.dispatch(method,path,data or {},who)
    def denied(self,code,action):
        with self.assertRaises(ApiError) as error:action()
        self.assertEqual(code,error.exception.status)
    def grant(self,granted=True):return self.call('POST',f'/enrollment/children/{self.child}/consent',{'granted':granted,'consentVersion':VERSION})
    def submit(self):
        self.grant()
        ticket=self.call('POST','/enrollment/tickets',{'consent':True,'consentVersion':VERSION},'child')['id']
        response=self.call('POST','/enrollment/tickets/'+ticket,{'image':base64.b64encode(self.photo).decode()},'child')
        return response['caseId']
    def decide(self,rid,action='approved',who='other'):
        if action=='approved':self.call('GET',f'/admin/enrollments/{rid}/photo',who=who)
        return self.call('POST',f'/admin/enrollments/{rid}/decision',{'action':action,'reason':'Cadastro revisado conforme os dados apresentados.','captureUsable':True,'dataReviewed':True},who)
    def test_pending_blocks_social_and_human_decision_unlocks(self):
        for path in ['/posts','/stories','/profiles','/conversations']:
            self.denied(403,lambda:self.call('GET',path,who='child'))
        rid=self.submit()
        self.assertEqual('pending',self.call('GET','/enrollment/status',who='child')['state'])
        self.denied(403,lambda:self.call('GET','/posts',who='child'))
        self.decide(rid)
        self.assertEqual([],self.call('GET','/posts',who='child')['items'])
        self.assertEqual('approved',self.call('GET','/me',who='child')['enrollmentState'])
        self.assertEqual([],self.r.rows('SELECT * FROM review_photos'))
        self.denied(409,lambda:self.decide(rid,'correction'))
    def test_consent_is_separate_and_only_current_guardian_can_grant(self):
        self.denied(403,lambda:self.call('POST','/enrollment/tickets',{'consent':True,'consentVersion':VERSION},'child'))
        self.denied(404,lambda:self.call('POST',f'/enrollment/children/{self.child}/consent',{'granted':True,'consentVersion':VERSION},'other'))
    def test_client_flags_cannot_approve_or_disable_the_review(self):
        self.call('PATCH','/me',{'approved':True,'reviewRequired':False,'enrollmentState':'approved'},'child')
        self.assertTrue(self.call('GET','/me',who='child')['reviewRequired'])
        self.denied(403,lambda:self.call('GET','/posts',who='child'))
    def test_photo_is_encrypted_private_and_never_social_media(self):
        rid=self.submit();cipher=self.r.one('SELECT cipher FROM review_photos')['cipher']
        self.assertNotIn(self.photo,cipher);self.assertNotEqual(self.photo,cipher)
        self.assertEqual([],self.r.rows('SELECT * FROM media'))
        self.denied(403,lambda:self.call('GET',f'/admin/enrollments/{rid}/photo'))
        image=self.call('GET',f'/admin/enrollments/{rid}/photo',who='other')
        self.assertTrue(base64.b64decode(image['data']).startswith(b'\xff\xd8'))
        exported=self.call('GET','/me/export',who='child')
        self.assertNotIn('cipher',str(exported));self.assertNotIn(base64.b64encode(self.photo).decode(),str(exported))
    def test_guardian_admin_cannot_review_own_family(self):
        rid=self.submit();self.r.execute('INSERT INTO administrators VALUES(?)',(self.parent,))
        self.denied(403,lambda:self.decide(rid,who='parent'))
        self.assertEqual([],self.call('GET','/admin/enrollments')['items'])
    def test_correction_and_appeal_resubmit_preserve_history_without_old_photos(self):
        rid=self.submit();self.decide(rid,'correction')
        self.assertEqual([],self.r.rows('SELECT * FROM review_photos'))
        newer=self.submit();self.assertNotEqual(rid,newer)
        self.denied(404,lambda:self.decide(rid))
        self.decide(newer,'additional_review')
        self.assertIsNotNone(self.r.one('SELECT * FROM review_photos WHERE review=?',(newer,)))
        self.decide(newer)
        self.assertEqual(2,len(self.r.rows('SELECT * FROM enrollment_reviews')))
    def test_approval_requires_photo_access_checklist_and_valid_family(self):
        rid=self.submit()
        body={'action':'approved','reason':'Dados de cadastro revisados.','captureUsable':True,'dataReviewed':True}
        self.denied(400,lambda:self.call('POST',f'/admin/enrollments/{rid}/decision',body,'other'))
        self.call('GET',f'/admin/enrollments/{rid}/photo',who='other')
        self.identity.tokens['parent']['email_verified']=False
        self.denied(403,lambda:self.call('POST',f'/admin/enrollments/{rid}/decision',body,'other'))
    def test_revoke_blocks_previously_approved_and_cancels_captures(self):
        rid=self.submit();self.decide(rid);self.grant(False)
        self.denied(403,lambda:self.call('GET','/posts',who='child'))
        self.denied(404,lambda:self.call('GET',f'/admin/enrollments/{rid}/photo',who='other'))
        self.assertEqual('revoked',self.call('GET','/enrollment/status',who='child')['state'])
        self.assertEqual([1,0],[v['granted'] for v in self.r.rows('SELECT granted FROM review_consent_events ORDER BY created')])
    def test_expiry_requires_new_capture_and_never_auto_approves(self):
        rid=self.submit();self.r.execute('UPDATE review_photos SET expires=0')
        self.s.maintain()
        self.assertEqual('correction',self.call('GET','/enrollment/status',who='child')['state'])
        self.assertEqual([],self.r.rows('SELECT * FROM review_photos'))
        self.denied(409,lambda:self.decide(rid,'correction'))
    def test_revocation_during_decryption_prevents_delivery(self):
        rid=self.submit();vault=self.s.review_vault;original=vault.decrypt
        def decrypt(value):
            decoded=original(value);self.grant(False);return decoded
        vault.decrypt=decrypt
        self.denied(404,lambda:self.call('GET',f'/admin/enrollments/{rid}/photo',who='other'))
    def test_ticket_replay_rate_and_account_cascade(self):
        self.grant();ticket=self.call('POST','/enrollment/tickets',{'consent':True,'consentVersion':VERSION},'child')['id']
        body={'image':base64.b64encode(self.photo).decode()}
        self.call('POST','/enrollment/tickets/'+ticket,body,'child')
        self.denied(404,lambda:self.call('POST','/enrollment/tickets/'+ticket,body,'child'))
        self.r.execute('DELETE FROM users WHERE id=?',(self.child,))
        self.assertEqual([],self.r.rows('SELECT * FROM review_photos'))
        self.assertEqual([],self.r.rows('PRAGMA foreign_key_check'))
    def test_full_http_correction_then_approval_flow(self):
        import json,threading,urllib.request
        from http.server import ThreadingHTTPServer
        from server import Handler
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.service=self.s;server.origins=set()
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        def request(method,path,data=None,who='parent'):
            raw=json.dumps(data).encode() if data is not None else None
            req=urllib.request.Request(f'http://127.0.0.1:{server.server_port}'+path,data=raw,method=method,headers={'Content-Type':'application/json','Authorization':'Bearer '+who})
            with urllib.request.urlopen(req,timeout=10) as response:return json.load(response)
        try:
            request('POST',f'/enrollment/children/{self.child}/consent',{'granted':True,'consentVersion':VERSION})
            def capture():
                tid=request('POST','/enrollment/tickets',{'consent':True,'consentVersion':VERSION},'child')['id']
                return request('POST','/enrollment/tickets/'+tid,{'image':base64.b64encode(self.photo).decode()},'child')['caseId']
            first=capture()
            request('POST',f'/admin/enrollments/{first}/decision',{'action':'correction','reason':'Envie outra captura para continuar a revisão.'},'other')
            self.assertEqual('correction',request('GET','/enrollment/status',who='child')['state'])
            second=capture()
            self.assertEqual(second,request('GET','/admin/enrollments',who='other')['items'][0]['id'])
            request('GET',f'/admin/enrollments/{second}/photo',who='other')
            request('POST',f'/admin/enrollments/{second}/decision',{'action':'approved','reason':'Dados e captura revisados para o cadastro.','captureUsable':True,'dataReviewed':True},'other')
            self.assertEqual([],request('GET','/posts',who='child')['items'])
            self.assertEqual([],self.r.rows('SELECT * FROM review_photos'))
        finally:server.shutdown();thread.join(timeout=3);server.server_close()

if __name__=='__main__':unittest.main()
