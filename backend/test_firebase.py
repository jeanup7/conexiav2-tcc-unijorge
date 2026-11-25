import time
import unittest
from service import Service, Repository, ApiError

class FakeFirebase:
    def __init__(self):
        self.claims={'uid':'firebase-test','email':'firebase@example.com','email_verified':False,'auth_time':time.time()}
        self.revoked=False
        self.deleted=False
    def verify(self, bearer):
        if bearer!='signed-token' or self.revoked or self.deleted:
            raise ApiError(401,'Invalid token')
        return dict(self.claims)
    def revoke(self, uid): self.revoked=True
    def delete(self, uid): self.deleted=True

class FirebaseTests(unittest.TestCase):
    def setUp(self):
        self.repo=Repository(':memory:')
        self.identity=FakeFirebase()
        self.api=Service(self.repo,development=True,firebase=self.identity)
    def call(self, method, path, body=None):
        return self.api.dispatch(method,path,body or {},'signed-token')
    def register(self, birth='2000-01-01'):
        return self.call('POST','/auth/firebase',{'name':'Test','birth':birth,'guardianEmail':'guardian@example.com','email_verified':True,'approved':True})
    def expect(self, status, action):
        with self.assertRaises(ApiError) as caught: action()
        self.assertEqual(status,caught.exception.status)
    def test_signed_verification_controls_social_access(self):
        result=self.register()
        self.assertEqual(0,result['user']['verified'])
        self.expect(403,lambda:self.call('POST','/posts',{'text':'blocked'}))
        self.identity.claims['email_verified']=True
        self.assertEqual(1,self.call('GET','/me')['verified'])
        self.call('POST','/posts',{'text':'allowed'})
        self.identity.claims['email_verified']=False
        self.expect(403,lambda:self.call('GET','/posts'))
    def test_uid_mapping_is_idempotent_and_direct_minor_signup_is_rejected(self):
        self.identity.claims['email_verified']=True
        self.expect(403,lambda:self.register('2015-01-01'))
        first=self.register()
        second=self.register('2015-01-01')
        self.assertEqual(first['user']['id'],second['user']['id'])
        self.assertFalse(second['user']['needsGuardian'])
        self.assertEqual(1,len(self.repo.rows('SELECT * FROM firebase_identities')))
    def test_invalid_and_revoked_tokens_fail_closed(self):
        self.register()
        self.expect(401,lambda:self.api.dispatch('GET','/me',{},'client-forged-token'))
        self.call('POST','/auth/logout')
        self.assertTrue(self.identity.revoked)
        self.expect(401,lambda:self.call('GET','/me'))
    def test_no_email_linking_to_local_account(self):
        Service(self.repo,development=True).dispatch('POST','/auth/register',{'email':'firebase@example.com','password':'a sufficiently long password','name':'Local','birth':'2000-01-01'})
        self.expect(409,self.register)
        self.assertEqual([],self.repo.rows('SELECT * FROM firebase_identities'))
    def test_firebase_mode_rejects_legacy_auth_routes_and_local_sessions(self):
        self.register()
        for path in ['/auth/register','/auth/login','/auth/verify','/auth/refresh','/auth/recover','/auth/reset']:
            with self.subTest(path=path):self.expect(404,lambda:self.call('POST',path,{'email_verified':True}))
        local=self.api.session(self.repo.one('SELECT * FROM users'))['accessToken']
        self.expect(401,lambda:self.api.dispatch('GET','/me',{},local))
    def test_delete_requires_recent_auth_and_removes_both_accounts(self):
        self.register()
        self.identity.claims['auth_time']=time.time()-600
        self.expect(401,lambda:self.call('DELETE','/me'))
        self.assertFalse(self.identity.deleted)
        self.identity.claims['auth_time']=time.time()
        self.call('DELETE','/me')
        self.assertTrue(self.identity.deleted)
        self.assertEqual([],self.repo.rows('SELECT * FROM users'))
        self.assertEqual([],self.repo.rows('SELECT * FROM firebase_identities'))
    def test_missing_admin_configuration_is_actionable(self):
        api=Service(self.repo,development=True)
        self.expect(503,lambda:api.dispatch('POST','/auth/firebase',{},'signed-token'))
    def tearDown(self): self.repo.db.close()

class FirebaseSdkVerificationTests(unittest.TestCase):
    def setUp(self):
        from firebase_identity import FirebaseIdentity
        from firebase_admin import auth
        self.provider=FirebaseIdentity.__new__(FirebaseIdentity)
        self.provider.auth=auth
        self.provider.app=object()
    def test_admin_sdk_checks_revocation(self):
        from unittest.mock import patch
        with patch('firebase_admin.auth.verify_id_token',return_value={'uid':'signed-user'}) as verify:
            self.assertEqual('signed-user',self.provider.verify('id-token')['uid'])
            verify.assert_called_once_with('id-token',app=self.provider.app,check_revoked=True)
    def test_admin_rejects_forged_or_expired_tokens(self):
        from unittest.mock import patch
        from firebase_admin import auth
        for error in (auth.InvalidIdTokenError('invalid'),auth.ExpiredIdTokenError('expired',None),auth.UserNotFoundError('missing')):
            with patch('firebase_admin.auth.verify_id_token',side_effect=error):
                with self.assertRaises(ApiError) as caught: self.provider.verify('forged-token')
                self.assertEqual(401,caught.exception.status)
    def test_provider_outage_is_not_an_authenticated_session(self):
        from unittest.mock import patch
        with patch('firebase_admin.auth.verify_id_token',side_effect=RuntimeError('offline')):
            with self.assertRaises(ApiError) as caught: self.provider.verify('id-token')
            self.assertEqual(503,caught.exception.status)
