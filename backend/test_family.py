from test_image_data import png_bytes
import base64
import os
import tempfile
import time
import unittest
from service import Service, Repository, ApiError

class FamilyFirebase:
    def __init__(self):
        self.tokens={
            'parent':{'uid':'p','email':'parent@example.com','email_verified':True,'auth_time':time.time()},
            'other':{'uid':'o','email':'other@example.com','email_verified':True,'auth_time':time.time()},
            'child':{'uid':'c','email':'child@example.com','email_verified':False,'auth_time':time.time()},
        }
    def verify(self,token):
        if token not in self.tokens: raise ApiError(401,'Token inválido')
        return dict(self.tokens[token])
    def verified_email(self,uid):
        return next((v['email_verified'] for v in self.tokens.values() if v['uid']==uid),False)
    def revoke(self,uid): pass
    def delete(self,uid): pass

class FamilyTests(unittest.TestCase):
    def setUp(self):
        self.repo=Repository(':memory:')
        self.identity=FamilyFirebase()
        self.api=Service(self.repo,development=True,firebase=self.identity)
        self.parent=self.call('POST','/auth/firebase',{'name':'Parent','birth':'1990-01-01'})['user']
    def call(self,method,path,body=None,actor='parent'):
        return self.api.dispatch(method,path,body or {},actor)
    def child(self):
        return self.call('POST','/guardian/children',{'childToken':'child','name':'Nome privado','birth':'2015-01-01','consent':True})['user']
    def expect(self,status,action):
        with self.assertRaises(ApiError) as caught: action()
        self.assertEqual(status,caught.exception.status)
    def ready(self):
        child=self.child()
        self.identity.tokens['child']['email_verified']=True
        self.call('PATCH','/me',{'name':'Ninja','private':True},'child')
        return child
    def upload(self,actor='parent'):
        data=base64.b64encode(png_bytes()).decode()
        return self.call('POST','/media',{'mime':'image/png','data':data},actor)['id']
    def test_two_confirmations_and_nickname_required(self):
        self.identity.tokens['parent']['email_verified']=False
        self.expect(403,self.child)
        self.identity.tokens['parent']['email_verified']=True
        child=self.child()
        self.assertEqual('Novo perfil',child['name'])
        self.assertEqual(0,child['verified'])
        self.expect(403,lambda:self.call('GET','/posts',actor='child'))
        self.identity.tokens['child']['email_verified']=True
        self.expect(403,lambda:self.call('GET','/posts',actor='child'))
        self.call('PATCH','/me',{'name':'Ninja','private':True},'child')
        self.assertEqual([],self.call('GET','/posts',actor='child')['items'])
        self.assertEqual('Ninja',self.call('GET','/me',actor='child')['name'])
        self.identity.tokens['parent']['email_verified']=False
        self.expect(403,lambda:self.call('GET','/posts',actor='child'))
    def test_child_cannot_create_itself_or_edit_family_link(self):
        self.expect(403,lambda:self.call('POST','/auth/firebase',{'name':'Child','birth':'2015-01-01','approved':True},'child'))
        child=self.ready()
        self.expect(403,lambda:self.call('PATCH','/guardian/children/'+child['id'],{'state':'active'},'child'))
        self.expect(403,lambda:self.call('POST','/guardian/children',{'childToken':'child','consent':True},'child'))
    def test_only_linked_guardian_can_pause_and_read_family(self):
        child=self.ready()
        self.call('POST','/auth/firebase',{'name':'Other','birth':'1990-01-01'},'other')
        self.assertEqual([],self.call('GET','/guardian/children',actor='other')['items'])
        self.expect(404,lambda:self.call('PATCH','/guardian/children/'+child['id'],{'state':'paused'},'other'))
        self.expect(409,lambda:self.call('POST','/guardian/children',{'childToken':'child','name':'Other','birth':'2015-01-01','consent':True},'other'))
        self.call('PATCH','/guardian/children/'+child['id'],{'state':'paused'})
        self.expect(403,lambda:self.call('GET','/posts',actor='child'))
        self.call('PATCH','/guardian/children/'+child['id'],{'state':'active'})
        self.call('GET','/posts',actor='child')
        family=self.call('GET','/guardian/children')['items'][0]
        self.assertEqual('Nome privado',family['childName'])
        self.assertEqual('Ninja',family['name'])
    def test_guardian_deletion_removes_authorization(self):
        self.ready()
        self.call('DELETE','/me')
        self.assertEqual([],self.repo.rows('SELECT * FROM guardian_links'))
        self.expect(403,lambda:self.call('GET','/posts',actor='child'))
    def test_avatar_ownership_privacy_and_cleanup(self):
        child=self.ready()
        image=self.upload('child')
        self.call('POST','/me/avatar',{'media':image},'child')
        self.assertEqual(image,self.call('GET','/me',actor='child')['avatar'])
        self.expect(404,lambda:self.call('GET','/media/'+image))
        foreign=self.upload()
        self.expect(400,lambda:self.call('POST','/me/avatar',{'media':foreign},'child'))
        request=self.call('POST','/contacts',{'target':child['id']})['requestId']
        self.call('POST','/contacts/approve',{'target':self.parent['id']},'child')
        self.call('PATCH','/guardian/children/'+child['id']+'/contacts/'+request,{'approved':True})
        self.assertEqual('image/png',self.call('GET','/media/'+image)['mime'])
        self.call('POST','/blocks',{'target':child['id']})
        self.expect(404,lambda:self.call('GET','/media/'+image))
        from maintenance import purge
        purge(self.repo)
        self.assertIsNotNone(self.repo.one('SELECT data FROM media WHERE id=?',(image,)))
        self.call('DELETE','/me/avatar',actor='child')
        self.assertIsNone(self.repo.one('SELECT data FROM media WHERE id=?',(image,)))
    def test_avatar_and_posts_are_binary_and_persist_after_reopen(self):
        handle,path=tempfile.mkstemp(suffix='.sqlite3');os.close(handle)
        repo=Repository(path)
        try:
            api=Service(repo,development=True,firebase=self.identity)
            api.dispatch('POST','/auth/firebase',{'name':'Parent','birth':'1990-01-01'},'parent')
            image=api.dispatch('POST','/media',{'mime':'image/png','data':base64.b64encode(png_bytes()).decode()},'parent')['id']
            api.dispatch('POST','/me/avatar',{'media':image},'parent')
            api.dispatch('POST','/posts',{'text':'Photo','mediaItems':[image]},'parent')
            self.assertEqual('blob',repo.one('SELECT typeof(data) AS type FROM media')['type'])
            repo.db.close();repo=Repository(path);api=Service(repo,development=True,firebase=self.identity)
            self.assertEqual(image,api.dispatch('GET','/me',{},'parent')['avatar'])
            self.assertEqual([image],api.dispatch('GET','/posts',{},'parent')['items'][0]['mediaItems'])
        finally: repo.db.close();os.unlink(path)
    def tearDown(self):self.repo.db.close()
