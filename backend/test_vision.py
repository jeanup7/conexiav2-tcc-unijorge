import base64
from io import BytesIO
import json
import time
import unittest
from PIL import Image
from repository import Repository
from service import Service
from security import ApiError
from test_family import FamilyFirebase
from vision import VERSION
from vision_models import decision
from evaluate_vision import summarize

class Provider:
    def analyze(self,contents,challenge):
        self.contents=contents
        return {'result':'experimental_signals_only','ageBand':'3-9','padScore':.95,'grantsAccess':True}

class VisionTests(unittest.TestCase):
    def setUp(self):
        self.r=Repository(':memory:');self.addCleanup(self.r.db.close)
        self.identity=FamilyFirebase();self.provider=Provider()
        self.s=Service(self.r,development=True,firebase=self.identity,vision_models=self.provider)
        self.parent=self.call('POST','/auth/firebase',{'name':'Parent','birth':'1990-01-01'})['user']['id']
        self.other=self.call('POST','/auth/firebase',{'name':'Other','birth':'1990-01-01'},'other')['user']['id']
        self.child=self.call('POST','/guardian/children',{'childToken':'child','name':'Private name','birth':'2014-01-01','consent':True})['user']['id']
        self.identity.tokens['child']['email_verified']=True
        self.frames=[]
        for color in ('red','green','blue'):
            image=Image.new('RGB',(320,320),color);output=BytesIO();image.save(output,format='JPEG')
            self.frames.append(base64.b64encode(output.getvalue()).decode())
    def call(self,method,path,data=None,who='parent'):return self.s.dispatch(method,path,data or {},who)
    def denied(self,status,action):
        with self.assertRaises(ApiError) as error:action()
        self.assertEqual(status,error.exception.status)
    def consent(self,granted=True,who='parent'):
        return self.call('POST',f'/vision/children/{self.child}/consent',{'granted':granted,'consentVersion':VERSION},who)
    def session(self,who='parent'):
        value=self.call('POST','/vision/sessions',{'consent':True,'consentVersion':VERSION},who)
        self.r.execute('UPDATE vision_sessions SET created=created-3 WHERE id=?',(value['id'],))
        return value['id']
    def submit(self,sid,who='parent',frames=None):return self.call('POST',f'/vision/sessions/{sid}/capture',{'frames':self.frames if frames is None else frames},who)
    def test_minors_need_separate_guardian_permission_and_both_emails(self):
        self.denied(403,lambda:self.session('child'))
        self.denied(404,lambda:self.consent(who='other'))
        self.consent();self.session('child')
        self.identity.tokens['parent']['email_verified']=False
        self.denied(403,lambda:self.session('child'))
    def test_own_session_is_one_shot_and_never_approves_access(self):
        sid=self.session();self.denied(409,lambda:self.submit(sid,'other'))
        result=self.submit(sid)['result']
        self.assertFalse(result['grantsAccess'])
        self.denied(409,lambda:self.submit(sid))
        self.denied(404,lambda:self.call('GET','/vision/sessions/'+sid,who='other'))
        stored=self.r.one('SELECT result FROM vision_sessions WHERE id=?',(sid,))['result']
        self.assertNotIn(self.frames[0],stored)
        self.assertEqual([],self.r.rows('SELECT * FROM media'))
        self.assertEqual(3,len(self.provider.contents))
    def test_expired_cancelled_and_repeated_frames_are_rejected(self):
        sid=self.session();self.denied(400,lambda:self.submit(sid,frames=[self.frames[0]]*3))
        self.r.execute('UPDATE vision_sessions SET expires=0 WHERE id=?',(sid,))
        self.denied(409,lambda:self.submit(sid))
        sid=self.session();self.call('DELETE','/vision/sessions/'+sid)
        self.denied(409,lambda:self.submit(sid))
    def test_revocation_during_inference_discards_the_result(self):
        self.consent();sid=self.session('child')
        def analyze(*args):self.consent(False);return {'result':'experimental_signals_only'}
        self.provider.analyze=analyze
        self.denied(403,lambda:self.submit(sid,'child'))
        self.assertEqual([],self.r.rows('SELECT * FROM vision_sessions'))
    def test_api_lock_is_not_held_during_inference(self):
        import threading
        acquired=[]
        def analyze(*args):
            def worker():
                with self.r.lock:acquired.append(True)
            t=threading.Thread(target=worker);t.start();t.join(1)
            self.assertEqual([True],acquired)
            return {'result':'inconclusive'}
        self.provider.analyze=analyze;self.submit(self.session())
    def test_model_failure_is_inconclusive_and_captures_are_not_persisted(self):
        def failed(*args):raise RuntimeError('private provider detail')
        self.provider.analyze=failed
        value=self.submit(self.session())
        self.assertEqual('inconclusive',value['result']['result'])
        self.assertNotIn('private provider detail',json.dumps(value))
        self.assertEqual([],self.r.rows('SELECT * FROM media'))
    def test_rate_limit_cleanup_and_cascade(self):
        for _ in range(6):self.session()
        self.denied(429,self.session)
        self.r.execute('UPDATE vision_sessions SET created=0');self.s.maintain()
        self.assertEqual([],self.r.rows('SELECT * FROM vision_sessions'))
        self.denied(429,self.session)
        self.r.execute('UPDATE vision_limits SET reset=0')
        self.session();self.r.execute('DELETE FROM users WHERE id=?',(self.parent,))
        self.assertEqual([],self.r.rows('SELECT * FROM vision_sessions'))
    def test_missing_models_fail_closed_without_affecting_normal_profile(self):
        self.s.vision_models=None
        self.assertFalse(self.call('GET','/vision/status')['enabled'])
        self.denied(503,self.session)
        self.assertEqual(self.parent,self.call('GET','/me')['id'])
    def test_age_boundary_and_invalid_numbers_never_become_verified(self):
        self.assertEqual('inconclusive',decision('10-19',.99,.99,True))
        self.assertEqual('inconclusive',decision('3-9',float('nan'),.9,True))
        self.assertEqual('presentation_risk',decision('3-9',.99,.1,True))
        self.assertEqual('inconclusive',decision('3-9',.99,.99,False))
    def test_cancellation_does_not_reset_the_durable_quota(self):
        for _ in range(6):
            sid=self.session();self.call('DELETE','/vision/sessions/'+sid)
        self.denied(429,self.session)
    def test_old_consent_version_is_not_accepted(self):
        self.consent()
        self.r.execute("UPDATE vision_consents SET version='old'")
        self.denied(403,lambda:self.session('child'))
    def test_comparison_metrics_have_known_denominators_and_no_fabricated_accuracy(self):
        self.assertIsNone(summarize([])['padAPCEROnProcessedAttacks'])
        rows=[{'processed':True,'presentation':'live','expectedAgeBand':'3-9','ageBand':'3-9','padScore':.9,'ageOnlySignal':True,'combinedSignal':True,'latencyMs':10},
              {'processed':True,'presentation':'screen','expectedAgeBand':None,'ageBand':'3-9','padScore':.2,'ageOnlySignal':True,'combinedSignal':False,'latencyMs':20},
              {'processed':False}]
        result=summarize(rows)
        self.assertEqual(0,result['padAPCEROnProcessedAttacks'])
        self.assertEqual(1,result['ageOnlyBaselineAttackAcceptance'])
        self.assertEqual(1,result['ageBandAccuracyOnLabelledLive'])
        self.assertEqual(15,result['meanInferenceMs'])

if __name__=='__main__':unittest.main()
