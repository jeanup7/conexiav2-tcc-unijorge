"""Transparent, first-party family activity: no private messages or inferred traits."""
import time
from datetime import datetime, timezone
from security import ApiError, token, age

CATEGORIES={'anime':'Animes','games':'Jogos','sports':'Esportes','music':'Música','education':'Educação','art':'Arte','other':'Outros'}

class Supervision:
    def __init__(self,service): self.s=service; self.r=service.repo
    def child(self,actor,child_id=None):
        if child_id is None:
            if age(actor['birth'])>=18: raise ApiError(403,'Esta tela pertence ao perfil do menor.')
            child=actor
            link=self.s.guardian_link(child)
            if not link: raise ApiError(404,'Vínculo indisponível.')
        else:
            if age(actor['birth'])<18 or not actor['verified']: raise ApiError(403,'Use a conta do responsável verificado.')
            link=self.r.one('SELECT * FROM guardian_links WHERE child=? AND guardian=?',(child_id,actor['id']))
            child=self.r.one('SELECT * FROM users WHERE id=?',(child_id,))
            if not link or not child or age(child['birth'])>=18: raise ApiError(404,'Vínculo indisponível.')
        return child,link
    def post(self,child,pid):
        if not pid: return None
        try: post=dict(self.s.post(child,pid))
        except ApiError: return None
        if post['story']:return None
        images=self.r.rows('SELECT media FROM post_media WHERE post=? ORDER BY position',(pid,))
        category=self.r.one('SELECT category FROM post_categories WHERE post=?',(pid,))
        return {'id':pid,'text':post['text'],'author':self.s.public(self.r.one('SELECT * FROM users WHERE id=?',(post['user'],))),
                'mediaItems':[v['media'] for v in images] or ([post['media']] if post['media'] else []),'category':category['category'] if category else 'other'}
    def record(self,child,pid,data):
        if age(child['birth'])>=18: raise ApiError(403,'O acompanhamento está disponível para o perfil vinculado do menor.')
        self.s.active(child)
        self.child(child)
        if self.s.post(child,pid)['story']:
            raise ApiError(400,'Stories não fazem parte do acompanhamento do feed.')
        milliseconds=data.get('visibleMs')
        if isinstance(milliseconds,bool) or not isinstance(milliseconds,int) or not 2000<=milliseconds<=60000:
            raise ApiError(400,'Tempo de exibição inválido.')
        now=time.time(); day=datetime.fromtimestamp(now,timezone.utc).strftime('%Y-%m-%d')
        category=self.r.one('SELECT category FROM post_categories WHERE post=?',(pid,))
        self.r.execute('INSERT INTO feed_views VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(child,post_key,day) DO UPDATE SET last_seen=excluded.last_seen',(token(),child['id'],pid,pid,category['category'] if category else 'other',day,now,now))
        return {'ok':True}
    def activity(self,actor,child_id,data):
        child,link=self.child(actor,child_id)
        try: days=int(data.get('days',7))
        except (ValueError,TypeError): raise ApiError(400,'Período inválido.')
        if days not in (7,30): raise ApiError(400,'Escolha 7 ou 30 dias.')
        now=time.time()
        self.r.execute('DELETE FROM feed_views WHERE last_seen<?',(now-30*86400,))
        rows=self.r.rows('SELECT * FROM feed_views WHERE child=? AND last_seen>=? ORDER BY last_seen DESC',(child['id'],now-days*86400))
        counts={}
        for row in rows: counts[row['category']]=counts.get(row['category'],0)+1
        history=[{'id':row['id'],'seenAt':row['last_seen'],'category':row['category'],'post':self.post(child,row['post'])} for row in rows[:50]]
        topics=self.r.rows('SELECT id,post,creator,state,created FROM family_discussions WHERE child=? AND guardian=? ORDER BY created DESC LIMIT 50',(child['id'],link['guardian']))
        for topic in topics:
            topic['requestedBy']='child' if topic['creator']==child['id'] else 'guardian'
            topic['post']=self.post(child,topic['post'])
            del topic['creator']
        return {'child':{'id':child['id'],'name':child['name']},'days':days,'total':len(rows),'historyLimit':50,
                'categories':[{'id':key,'name':CATEGORIES.get(key,CATEGORIES['other']),'count':value} for key,value in sorted(counts.items(),key=lambda x:-x[1])],
                'history':history,'discussions':topics,'retentionDays':30,
                'notice':'Posts exibidos por pelo menos 2 segundos com ao menos metade visível. Um registro por postagem por dia. Ver não significa gostar. Categorias informadas pelo autor; mensagens privadas não são compartilhadas.'}
    def discuss(self,actor,child_id,data):
        child,link=self.child(actor,child_id)
        self.s.active(actor)
        pid=data.get('post')
        if not isinstance(pid,str): raise ApiError(400,'Publicação inválida.')
        if not self.post(child,pid): raise ApiError(404,'Publicação indisponível.')
        if actor['id']!=child['id'] and not self.r.one('SELECT id FROM feed_views WHERE child=? AND post=? AND last_seen>=?',(child['id'],pid,time.time()-30*86400)) and not self.r.one('SELECT id FROM family_discussions WHERE child=? AND guardian=? AND post=?',(child['id'],link['guardian'],pid)):
            raise ApiError(404,'Publicação não compartilhada no acompanhamento.')
        previous=self.r.one("SELECT id FROM family_discussions WHERE child=? AND guardian=? AND post=? AND state='open'",(child['id'],link['guardian'],pid))
        if previous: return {'id':previous['id']}
        did=token()
        self.r.execute('INSERT INTO family_discussions VALUES(?,?,?,?,?,?,?)',(did,child['id'],link['guardian'],pid,actor['id'],'open',time.time()))
        self.s.notification(link['guardian'] if actor['id']==child['id'] else child['id'],'Uma publicação foi marcada para conversar em família.')
        return {'id':did}
    def resolve(self,actor,did,data):
        topic=self.r.one('SELECT * FROM family_discussions WHERE id=?',(did,))
        if not topic or actor['id'] not in (topic['child'],topic['guardian']): raise ApiError(404,'Conversa indisponível.')
        child,link=self.child(actor,None if actor['id']==topic['child'] else topic['child'])
        if link['guardian']!=topic['guardian']: raise ApiError(404,'Vínculo indisponível.')
        state=data.get('state')
        if state not in ('open','resolved'): raise ApiError(400,'Situação inválida.')
        self.r.execute('UPDATE family_discussions SET state=? WHERE id=?',(state,did))
        return {'ok':True}
    def media(self,actor,child_id,pid,mid):
        child,link=self.child(actor,child_id)
        exposed=self.r.one('SELECT id FROM feed_views WHERE child=? AND post=? AND last_seen>=?',(child['id'],pid,time.time()-30*86400)) or self.r.one('SELECT id FROM family_discussions WHERE child=? AND guardian=? AND post=?',(child['id'],link['guardian'],pid))
        post=self.post(child,pid)
        if not exposed or not post or mid not in post['mediaItems']: raise ApiError(404,'Imagem indisponível.')
        row=self.r.one('SELECT mime,data FROM media WHERE id=?',(mid,))
        if not row: raise ApiError(404,'Imagem indisponível.')
        return self.s.read_media(mid)
