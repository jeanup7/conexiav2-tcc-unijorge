import unittest
import time
import test_family
from service import ApiError

class SupervisionTests(unittest.TestCase):
    setUp = test_family.FamilyTests.setUp
    call = test_family.FamilyTests.call
    child = test_family.FamilyTests.child
    ready = test_family.FamilyTests.ready
    expect = test_family.FamilyTests.expect
    upload = test_family.FamilyTests.upload
    def setUp(self):
        test_family.FamilyTests.setUp(self)
        self.kid = self.ready()
        self.base = '/guardian/children/' + self.kid['id']
        self.call('POST','/auth/firebase',{'name':'Other','birth':'1990-01-01'},'other')
        self.call('PATCH','/me',{'name':'Other','private':False},'other')
    def tearDown(self):
        self.repo.db.close()
    def post(self,category='anime',media=None):
        return self.call('POST','/posts',{'text':'Uma postagem de teste','category':category, **({'mediaItems':[media]} if media else {})},'other')['id']
    def view(self,pid):
        return self.call('POST','/posts/'+pid+'/view',{'visibleMs':2000},'child')
    def activity(self):
        return self.call('GET',self.base+'/activity')
    def test_summary_is_transparent_and_deduplicated(self):
        pid=self.post(); self.view(pid); self.view(pid)
        parent=self.activity(); child=self.call('GET','/family/activity',actor='child')
        self.assertEqual(parent,child)
        self.assertEqual(1,parent['total'])
        self.assertEqual('anime',parent['categories'][0]['id'])
        self.assertEqual(pid,parent['history'][0]['post']['id'])
        self.expect(404,lambda:self.call('GET',self.base+'/activity',actor='other'))
        self.expect(400,lambda:self.call('GET',self.base+'/activity',{'days':60}))
    def test_invalid_display_and_category(self):
        pid=self.post()
        for value in [True,1999,60001,'2000',None]:
            self.expect(400,lambda:self.call('POST','/posts/'+pid+'/view',{'visibleMs':value},'child'))
        self.expect(403,lambda:self.call('POST','/posts/'+pid+'/view',{'visibleMs':2000},'other'))
        self.expect(400,lambda:self.post([]))
        self.assertEqual(0,self.activity()['total'])
    def test_conversations_can_be_started_and_resolved_by_both(self):
        pid=self.post()
        self.expect(404,lambda:self.call('POST',self.base+'/discussions',{'post':pid}))
        topic=self.call('POST','/family/discussions',{'post':pid},'child')['id']
        self.assertEqual(topic,self.call('POST',self.base+'/discussions',{'post':pid})['id'])
        self.assertEqual('child',self.activity()['discussions'][0]['requestedBy'])
        self.expect(404,lambda:self.call('PATCH','/family/discussions/'+topic,{'state':'resolved'},'other'))
        self.call('PATCH','/family/discussions/'+topic,{'state':'resolved'})
        self.assertEqual('resolved',self.call('GET','/family/activity',actor='child')['discussions'][0]['state'])
        self.call('PATCH','/family/discussions/'+topic,{'state':'open'},'child')
        self.assertEqual('open',self.activity()['discussions'][0]['state'])
        second=self.post('sports'); self.view(second)
        self.call('POST',self.base+'/discussions',{'post':second})
        self.assertEqual('guardian',self.activity()['discussions'][0]['requestedBy'])
    def test_history_rechecks_current_visibility_and_deleted_posts(self):
        pid=self.post(); self.view(pid)
        self.call('PATCH','/me',{'name':'Other','private':True},'other')
        self.assertIsNone(self.activity()['history'][0]['post'])
        self.call('PATCH','/me',{'name':'Other','private':False},'other')
        self.call('DELETE','/posts/'+pid,actor='other')
        self.assertIsNone(self.activity()['history'][0]['post'])
        self.assertEqual(1,self.activity()['total'])
    def test_only_shared_images_and_no_general_private_access(self):
        image=self.upload('other'); pid=self.post(media=image)
        endpoint=self.base+'/activity/posts/'+pid+'/media/'+image
        self.expect(404,lambda:self.call('GET',endpoint))
        self.view(pid)
        self.assertEqual('image/png',self.call('GET',endpoint)['mime'])
        self.assertEqual(self.call('GET',endpoint),self.call('GET','/family/activity/posts/'+pid+'/media/'+image,actor='child'))
        self.expect(404,lambda:self.call('GET',endpoint,actor='other'))
        self.call('PATCH','/me',{'name':'Other','private':True},'other')
        other_id=self.repo.one("SELECT user FROM firebase_identities WHERE uid='o'")['user']
        request=self.call('POST','/contacts',{'target':other_id},'child')['requestId']
        self.call('POST','/contacts/approve',{'target':self.kid['id']},'other')
        self.call('PATCH',self.base+'/contacts/'+request,{'approved':True})
        self.assertEqual('image/png',self.call('GET',endpoint)['mime'])
        self.expect(404,lambda:self.call('GET','/media/'+image))
        self.call('POST','/blocks',{'target':self.kid['id']},'other')
        self.expect(404,lambda:self.call('GET',endpoint))
    def test_paused_child_can_inspect_but_cannot_record(self):
        pid=self.post(); self.view(pid)
        self.call('PATCH',self.base,{'state':'paused'})
        self.assertEqual(1,self.call('GET','/family/activity',actor='child')['total'])
        self.expect(403,lambda:self.view(pid))
    def test_retention_removes_old_history(self):
        pid=self.post(); self.view(pid)
        self.repo.execute('UPDATE feed_views SET last_seen=?',(time.time()-31*86400,))
        self.assertEqual(0,self.activity()['total'])
        self.assertEqual([],self.repo.rows('SELECT * FROM feed_views'))

if __name__=='__main__': unittest.main()
