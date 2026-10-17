from test_image_data import png_bytes
import unittest
from service import Service, Repository, ApiError, password_matches

class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.repo=Repository(':memory:')
        self.api=Service(self.repo,development=True)
        self.a=self.register('a@example.com','Alice')
        self.b=self.register('b@example.com','Beto')
    def register(self,email,name,birth='2000-01-01'):
        payload={'email':email,'name':name,'password':'correct horse battery staple','birth':birth,'guardianEmail':'guardian@example.com'}
        result=self.api.dispatch('POST','/auth/register',payload,ip=email)
        self.api.dispatch('POST','/auth/verify',{'token':result['developmentToken']},ip=email)
        return self.api.dispatch('POST','/auth/login',payload,ip=email)
    def call(self,method,path,data=None,session=None):
        return self.api.dispatch(method,path,data or {},(session or self.a)['accessToken'],ip='test')
    def expect(self,status,fn):
        with self.assertRaises(ApiError) as cm: fn()
        self.assertEqual(status,cm.exception.status)
    def connect(self):
        self.call('POST','/contacts',{'target':self.b['user']['id']})
        self.call('POST','/contacts/approve',{'target':self.a['user']['id']},self.b)
    def test_password_only_salted_hash(self):
        row=self.repo.one('SELECT * FROM users WHERE id=?',(self.a['user']['id'],))
        self.assertNotEqual(row['password'],'correct horse battery staple')
        self.assertTrue(password_matches('correct horse battery staple',row['password']))
        other=self.repo.one('SELECT * FROM users WHERE id=?',(self.b['user']['id'],))
        self.assertNotEqual(row['password'],other['password'])
    def test_login_invalid_and_rate_limit(self):
        payload={'email':'missing@example.com','password':'bad'}
        for i in range(8): self.expect(401,lambda:self.api.dispatch('POST','/auth/login',payload,ip='bad'))
        self.expect(429,lambda:self.api.dispatch('POST','/auth/login',payload,ip='bad'))
    def test_refresh_rotates_and_logout_revokes(self):
        old=self.a
        self.a=self.call('POST','/auth/refresh',{'refreshToken':old['refreshToken']})
        self.expect(401,lambda:self.call('GET','/me',session=old))
        self.expect(401,lambda:self.call('POST','/auth/refresh',{'refreshToken':old['refreshToken']}))
        self.call('POST','/auth/logout')
        self.expect(401,lambda:self.call('GET','/me'))
    def test_minor_cannot_self_approve_or_publish(self):
        minor=self.register('child@example.com','Criança','2015-01-01')
        self.expect(403,lambda:self.call('POST','/posts',{'text':'hello'},minor))
        self.call('POST','/guardian/request',session=minor)
        self.assertFalse(self.call('GET','/guardian/status',session=minor)['approved'])
        self.expect(403,lambda:self.call('PATCH','/me',{'name':'Child','private':False},minor))
        self.expect(403,lambda:self.call('GET','/profiles',session=minor))
    def test_unverified_cannot_read_social_resources(self):
        self.repo.execute('UPDATE users SET verified=0 WHERE id=?',(self.a['user']['id'],))
        self.expect(403,lambda:self.call('GET','/posts'))
    def test_private_posts_and_resource_ownership(self):
        pid=self.call('POST','/posts',{'text':'private'})['id']
        self.assertEqual([],self.call('GET','/posts',session=self.b)['items'])
        self.expect(404,lambda:self.call('POST',f'/posts/{pid}/like',session=self.b))
        self.connect()
        self.assertEqual(pid,self.call('GET','/posts',session=self.b)['items'][0]['id'])
        self.expect(403,lambda:self.call('DELETE',f'/posts/{pid}',session=self.b))
        self.call('PATCH',f'/posts/{pid}',{'text':'updated'})
        self.assertEqual('updated',self.call('GET','/posts')['items'][0]['text'])
        self.call('DELETE',f'/posts/{pid}')
        self.assertEqual([],self.call('GET','/posts')['items'])
    def test_block_hides_posts_and_stops_messages(self):
        self.connect()
        pid=self.call('POST','/posts',{'text':'hello'})['id']
        self.call('POST','/blocks',{'target':self.a['user']['id']},self.b)
        self.assertEqual([],self.call('GET','/posts',session=self.b)['items'])
        self.expect(404,lambda:self.call('GET',f'/posts/{pid}/comments',session=self.b))
        self.expect(403,lambda:self.call('POST','/messages/'+self.b['user']['id'],{'text':'hello'}))
    def test_messages_require_contact_and_preference(self):
        endpoint='/messages/'+self.b['user']['id']
        self.expect(403,lambda:self.call('POST',endpoint,{'text':'hello'}))
        self.connect()
        self.expect(403,lambda:self.call('POST',endpoint,{'text':'hello'}))
        for session in (self.a,self.b): self.call('PATCH','/me',{'name':session['user']['name'],'messages':True},session)
        self.call('POST',endpoint,{'text':'hello'})
        rows=self.call('GET','/messages/'+self.a['user']['id'],session=self.b)['items']
        self.assertEqual('hello',rows[0]['text']); self.assertEqual(0,rows[0]['read'])
        self.call('POST','/messages/'+self.a['user']['id']+'/read',{'ids':[rows[0]['id']]},self.b)
        self.assertEqual(1,self.call('GET','/messages/'+self.a['user']['id'],session=self.b)['items'][0]['read'])
    def test_story_expiry_and_pagination(self):
        pid=self.call('POST','/stories',{'text':'temporary'})['id']
        self.assertEqual(1,len(self.call('GET','/stories')['items']))
        self.repo.execute('UPDATE posts SET expires=1 WHERE id=?',(pid,))
        self.assertEqual([],self.call('GET','/stories')['items'])
        for i in range(3): self.call('POST','/posts',{'text':str(i)})
        first=self.call('GET','/posts',{'limit':'2'})
        second=self.call('GET','/posts',{'cursor':str(first['nextCursor'])})
        self.assertEqual(2,len(first['items'])); self.assertEqual(1,len(second['items']))
    def test_likes_comments_reports_persist(self):
        pid=self.call('POST','/posts',{'text':'hello'})['id']
        self.call('POST',f'/posts/{pid}/like'); self.assertEqual(1,self.call('GET','/posts')['items'][0]['likes'])
        self.call('POST',f'/posts/{pid}/like'); self.assertEqual(0,self.call('GET','/posts')['items'][0]['likes'])
        self.call('POST',f'/posts/{pid}/comments',{'text':'nice'})
        self.assertEqual('nice',self.call('GET',f'/posts/{pid}/comments')['items'][0]['text'])
        result=self.call('POST','/reports',{'target':pid,'reason':'inadequado'})
        self.assertEqual(result['id'],self.call('GET','/reports')['items'][0]['id'])
        self.assertEqual([],self.call('GET','/reports',session=self.b)['items'])
    def test_reset_single_use_and_session_revocation(self):
        result=self.api.dispatch('POST','/auth/recover',{'email':'a@example.com'},ip='recover')
        body={'token':result['developmentToken'],'password':'new correct long password'}
        self.api.dispatch('POST','/auth/reset',body,ip='recover')
        self.expect(400,lambda:self.api.dispatch('POST','/auth/reset',body,ip='recover'))
        self.expect(401,lambda:self.call('GET','/me'))
    def test_media_validation(self):
        self.expect(400,lambda:self.call('POST','/media',{'mime':'image/png','data':'YWJj'}))
        self.expect(400,lambda:self.call('POST','/media',{'mime':'video/mp4','data':'YWJj'}))
    def test_account_deletion_cascades(self):
        pid=self.call('POST','/posts',{'text':'delete'})['id']
        self.call('POST',f'/posts/{pid}/comments',{'text':'comment'})
        self.expect(401,lambda:self.call('DELETE','/me',{'password':'wrong'}))
        self.call('DELETE','/me',{'password':'correct horse battery staple'})
        self.assertEqual([],self.repo.rows('SELECT * FROM posts'))
        self.assertEqual([],self.repo.rows('SELECT * FROM comments'))
        self.expect(401,lambda:self.call('GET','/me'))
    def test_input_validation(self):
        for body in ({'text':''},{'text':123}): self.expect(400,lambda:self.call('POST','/posts',body))
        self.expect(400,lambda:self.call('PATCH','/me',{'name':'A','private':'false'}))
        self.expect(400,lambda:self.call('GET','/posts',{'cursor':'bad'}))
    def test_expired_access_is_rejected(self):
        self.repo.execute('UPDATE sessions SET expires=1 WHERE user=?',(self.a['user']['id'],))
        self.expect(401,lambda:self.call('GET','/me'))
        refreshed=self.call('POST','/auth/refresh',{'refreshToken':self.a['refreshToken']})
        self.assertEqual(self.a['user']['id'],self.call('GET','/me',session=refreshed)['id'])
    def test_maintenance_removes_expired_story(self):
        from maintenance import purge
        pid=self.call('POST','/stories',{'text':'expired'})['id']
        self.repo.execute('UPDATE posts SET expires=1 WHERE id=?',(pid,))
        purge(self.repo)
        self.assertIsNone(self.repo.one('SELECT * FROM posts WHERE id=?',(pid,)))
    def test_password_spaces_are_preserved(self):
        payload={'email':'spaces@example.com','name':'Space','birth':'2000-01-01','password':'  significant spaces  '}
        self.api.dispatch('POST','/auth/register',payload,ip='spaces')
        result=self.api.dispatch('POST','/auth/login',payload,ip='spaces')
        self.assertIsNotNone(result['accessToken'])
        payload['password']=payload['password'].strip()
        self.expect(401,lambda:self.api.dispatch('POST','/auth/login',payload,ip='spaces'))
    def test_unconfigured_provider_fails_closed(self):
        from providers import UnconfiguredGuardianProvider
        self.assertFalse(UnconfiguredGuardianProvider().verify_callback(b'{"approved":true}','fake').verified)

    def upload(self, session=None):
        import base64
        return self.call('POST','/media',{'mime':'image/png','data':base64.b64encode(png_bytes()).decode()},session)['id']
    def test_carousel_order_ownership_and_visibility(self):
        images=[self.upload(),self.upload()]
        pid=self.call('POST','/posts',{'text':'gallery','mediaItems':images})['id']
        row=self.call('GET','/posts')['items'][0]
        self.assertEqual(images,row['mediaItems'])
        self.assertEqual(images[0],row['media'])
        self.expect(404,lambda:self.call('GET','/media/'+images[1],session=self.b))
        self.connect()
        self.assertEqual('image/png',self.call('GET','/media/'+images[1],session=self.b)['mime'])
        self.call('POST','/blocks',{'target':self.a['user']['id']},self.b)
        self.expect(404,lambda:self.call('GET','/media/'+images[1],session=self.b))
        self.call('DELETE','/posts/'+pid)
        self.assertEqual([],self.repo.rows('SELECT * FROM post_media'))
    def test_carousel_rejects_invalid_lists_before_creating_post(self):
        own=self.upload(); foreign=self.upload(self.b)
        for images in ([own,foreign],[own,own],[own]*11,'invalid',[None]):
            self.expect(400,lambda:self.call('POST','/posts',{'text':'gallery','mediaItems':images}))
        self.assertEqual([],self.repo.rows('SELECT * FROM posts'))
    def test_legacy_photo_and_gallery_survive_cleanup(self):
        from maintenance import purge
        images=[self.upload(),self.upload()]
        legacy=self.call('POST','/posts',{'text':'legacy','media':images[0]})['id']
        self.repo.execute('DELETE FROM post_media WHERE post=?',(legacy,))
        gallery=self.call('POST','/posts',{'text':'gallery','mediaItems':images})['id']
        orphan=self.upload()
        purge(self.repo,orphan_grace_seconds=0)
        self.assertIsNone(self.repo.one('SELECT * FROM media WHERE id=?',(orphan,)))
        posts={p['id']:p for p in self.call('GET','/posts')['items']}
        self.assertEqual(images,posts[gallery]['mediaItems'])
        self.assertEqual([images[0]],posts[legacy]['mediaItems'])
    def test_profile_details_and_filtered_posts_obey_privacy(self):
        owner=self.a['user']['id']
        self.expect(404,lambda:self.call('GET','/profiles/'+owner,session=self.b))
        self.expect(404,lambda:self.call('GET','/posts',{'user':owner},self.b))
        self.connect()
        profile=self.call('GET','/profiles/'+owner,session=self.b)
        self.assertEqual({'id','name','bio','private','avatar'},set(profile))
        self.call('POST','/posts',{'text':'other'},self.b)
        for i in range(3): self.call('POST','/posts',{'text':str(i)})
        first=self.call('GET','/posts',{'user':owner,'limit':'2'},self.b)
        second=self.call('GET','/posts',{'user':owner,'cursor':str(first['nextCursor'])},self.b)
        self.assertEqual(2,len(first['items']))
        self.assertEqual(1,len(second['items']))
        self.assertTrue(all(p['user']==owner for p in first['items']+second['items']))
        self.call('POST','/blocks',{'target':owner},self.b)
        self.expect(404,lambda:self.call('GET','/profiles/'+owner,session=self.b))
    def tearDown(self): self.repo.db.close()

if __name__=='__main__': unittest.main()
