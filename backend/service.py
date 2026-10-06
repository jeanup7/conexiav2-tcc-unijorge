"""Application services: resource authorization and social workflows."""
import base64
import sqlite3
import time
from threading import RLock
from repository import Repository
from security import ApiError, token, digest, password_hash, password_matches, text, email, age, password as validate_password

class Service:
    def __init__(self, repo, development=False):
        self.repo, self.development = repo, development
        self.lock = RLock()
        self.limits = {}
    def audit(self, event, user):
        self.repo.execute('INSERT INTO audit VALUES(?,?,?,?)', (token(),event,digest(user),time.time()))
    def limit(self, key, ceiling=60, window=60):
        now=time.time()
        self.limits={k:v for k,v in self.limits.items() if v[0]>now-window}
        start,count=self.limits.get(key,(now,0))
        if count >= ceiling: raise ApiError(429,'Muitas tentativas. Aguarde antes de tentar novamente.')
        self.limits[key]=(start,count+1)
    def user(self, bearer):
        row=self.repo.one('SELECT u.* FROM users u JOIN sessions s ON s.user=u.id WHERE s.access=? AND s.expires>?',(digest(bearer),time.time()))
        if not row: raise ApiError(401,'Sessão expirada. Entre novamente.')
        return row
    def active(self,u):
        if not u['verified'] or (age(u['birth'])<18 and not u['approved']):
            raise ApiError(403,'Confirme o e-mail e conclua a verificação do responsável.')
    def public(self,u,own=False):
        result={k:u[k] for k in ('id','name','bio','private')}
        if own: result.update({k:u[k] for k in ('email','verified','approved','messages')},needsGuardian=age(u['birth'])<18)
        return result
    def session(self,u):
        access,refresh=token(),token()
        self.repo.execute('INSERT INTO sessions VALUES(?,?,?,?,?)',(digest(access),digest(refresh),u['id'],time.time()+900,time.time()+86400*7))
        return {'accessToken':access,'refreshToken':refresh,'user':self.public(u,True)}
    def challenge(self,u,kind):
        raw=token()
        self.repo.execute('DELETE FROM challenges WHERE user=? AND kind=?',(u['id'],kind))
        self.repo.execute('INSERT INTO challenges VALUES(?,?,?,?)',(digest(raw),u['id'],kind,time.time()+3600))
        # Production must supply email delivery; never log tokens or expose them there.
        return {'developmentToken':raw} if self.development else {}
    def blocked(self,a,b):
        return bool(self.repo.one('SELECT 1 FROM blocks WHERE (user=? AND target=?) OR (user=? AND target=?)',(a,b,b,a)))
    def contact(self,a,b):
        return bool(self.repo.one('SELECT 1 FROM contacts WHERE user=? AND target=? AND approved=1',(a,b)))
    def visible(self,u,owner):
        if u['id']==owner['id']: return True
        if self.blocked(u['id'],owner['id']): return False
        if not owner['verified'] or (age(owner['birth'])<18 and not owner['approved']): return False
        return not owner['private'] or self.contact(u['id'],owner['id'])
    def post(self,u,pid):
        p=self.repo.one('SELECT * FROM posts WHERE id=?',(pid,))
        if not p or (p['expires'] and p['expires']<=time.time()): raise ApiError(404,'Publicação indisponível')
        owner=self.repo.one('SELECT * FROM users WHERE id=?',(p['user'],))
        if not self.visible(u,owner): raise ApiError(404,'Publicação indisponível')
        return p
    def notification(self,user,message):
        self.repo.execute('INSERT INTO notifications VALUES(?,?,?,?)',(token(),user,message,time.time()))
    def dispatch(self,method,path,data,bearer='',ip='local'):
        with self.lock:
            self.limit(('ip',ip),180)
            return self._dispatch(method,path,data,bearer,ip)
    def _dispatch(self,method,path,data,bearer,ip):
        r=self.repo
        parts=path.strip('/').split('/')
        if path=='/health': return {'status':'ok','storage':'sqlite','development':self.development}
        if path.startswith('/auth/'):
            self.limit(('auth',ip),30)
            if path=='/auth/register' and method=='POST':
                mail=email(data); password=validate_password(data); name=text(data,'name',1,60)
                birth=text(data,'birth',10,10); years=age(birth)
                guardian=email(data,'guardianEmail') if years<18 else None
                if guardian==mail: raise ApiError(400,'Use um e-mail independente do responsável')
                uid=token()
                try: r.execute('INSERT INTO users(id,email,password,name,birth,guardian) VALUES(?,?,?,?,?,?)',(uid,mail,password_hash(password),name,birth,guardian))
                except sqlite3.IntegrityError: raise ApiError(409,'Não foi possível cadastrar essa conta')
                u=r.one('SELECT * FROM users WHERE id=?',(uid,)); self.audit('account.created',uid)
                return {'message':'Conta criada. Verifique seu e-mail.',**self.challenge(u,'verify')}
            if path=='/auth/login' and method=='POST':
                mail=email(data); self.limit(('login',digest(mail)),8,900)
                pw=data.get('password','')
                if not isinstance(pw,str) or len(pw)>128: raise ApiError(400,'Senha inválida')
                u=r.one('SELECT * FROM users WHERE email=?',(mail,))
                # Constant-cost hashing for unknown accounts.
                encoded=u['password'] if u else '00'*16+':'+'00'*64
                valid=password_matches(pw,encoded)
                if not u or not valid: raise ApiError(401,'E-mail ou senha incorretos')
                self.audit('session.login',u['id']); return self.session(u)
            if path=='/auth/refresh' and method=='POST':
                old=r.one('SELECT * FROM sessions WHERE refresh=? AND refresh_expires>?',(digest(text(data,'refreshToken')),time.time()))
                if not old: raise ApiError(401,'Sessão expirada')
                r.execute('DELETE FROM sessions WHERE access=?',(old['access'],))
                return self.session(r.one('SELECT * FROM users WHERE id=?',(old['user'],)))
            if path=='/auth/recover' and method=='POST':
                u=r.one('SELECT * FROM users WHERE email=?',(email(data),))
                result=self.challenge(u,'reset') if u else {}
                return {'message':'Se a conta existir, receberá as instruções.',**result}
            if path in ('/auth/verify','/auth/reset') and method=='POST':
                kind='verify' if path.endswith('verify') else 'reset'
                c=r.one('SELECT * FROM challenges WHERE token=? AND kind=? AND expires>?',(digest(text(data,'token')),kind,time.time()))
                if not c: raise ApiError(400,'Código inválido ou expirado')
                if kind=='reset':
                    pw=validate_password(data)
                    r.execute('UPDATE users SET password=? WHERE id=?',(password_hash(pw),c['user']))
                    r.execute('DELETE FROM sessions WHERE user=?',(c['user'],))
                else: r.execute('UPDATE users SET verified=1 WHERE id=?',(c['user'],))
                r.execute('DELETE FROM challenges WHERE token=?',(c['token'],))
                self.audit('account.'+kind,c['user']); return {'message':'Operação concluída'}
        u=self.user(bearer); uid=u['id']
        if path=='/auth/logout' and method=='POST':
            r.execute('DELETE FROM sessions WHERE access=?',(digest(bearer),)); return {'ok':True}
        if path=='/me' and method=='GET': return self.public(u,True)
        if path=='/me' and method=='PATCH':
            name=text(data,'name',1,60); bio=data.get('bio','')
            if not isinstance(bio,str) or len(bio)>180: raise ApiError(400,'Biografia muito longa')
            private=data.get('private',True); messages=data.get('messages',False)
            if not isinstance(private,bool) or not isinstance(messages,bool): raise ApiError(400,'Preferências inválidas')
            if age(u['birth'])<18 and not private: raise ApiError(403,'Perfis de menores permanecem privados')
            r.execute('UPDATE users SET name=?,bio=?,private=?,messages=? WHERE id=?',(name,bio,int(private),int(messages),uid))
            return self.public(r.one('SELECT * FROM users WHERE id=?',(uid,)),True)
        if path=='/me/export' and method=='GET':
            result={'profile':self.public(u,True)}
            for table,field in [('posts','user'),('comments','user'),('reports','user'),('blocks','user')]: result[table]=r.rows(f'SELECT * FROM {table} WHERE {field}=?',(uid,))
            result['messages']=r.rows('SELECT * FROM messages WHERE sender=? OR recipient=?',(uid,uid))
            return result
        if path=='/me' and method=='DELETE':
            pw=data.get('password','')
            if not isinstance(pw,str) or len(pw)>128: raise ApiError(400,'Senha inválida')
            if not password_matches(pw,u['password']): raise ApiError(401,'Senha incorreta')
            self.audit('account.deleted',uid); r.execute('DELETE FROM users WHERE id=?',(uid,)); return {'ok':True}
        if path=='/guardian/status': return {'required':age(u['birth'])<18,'approved':bool(u['approved']),'providerConfigured':False}
        if path=='/guardian/request' and method=='POST':
            self.audit('guardian.requested',uid)
            return {'message':'Vínculo pendente. Um provedor de verificação do responsável precisa ser configurado. Nenhuma aprovação foi concedida.'}
        if path=='/notifications' and method=='GET': return {'items':r.rows('SELECT id,text,created FROM notifications WHERE user=? ORDER BY created DESC LIMIT 50',(uid,))}
        if path=='/reports' and method=='GET': return {'items':r.rows('SELECT * FROM reports WHERE user=? ORDER BY created DESC',(uid,))}
        if path=='/reports' and method=='POST':
            reason=text(data,'reason',3,1000); target=text(data,'target',1,200); rid=token()
            r.execute('INSERT INTO reports(id,user,target,reason,created) VALUES(?,?,?,?,?)',(rid,uid,target,reason,time.time()))
            self.audit('report.created',uid); return {'id':rid,'status':'pending','message':'Registrada. Atendimento humano ainda precisa ser configurado.'}
        if path=='/blocks' and method=='GET': return {'items':r.rows('SELECT u.id,u.name FROM users u JOIN blocks b ON b.target=u.id WHERE b.user=?',(uid,))}
        if path=='/blocks' and method=='POST':
            target=text(data,'target')
            if target==uid or not r.one('SELECT id FROM users WHERE id=?',(target,)): raise ApiError(400,'Perfil inválido')
            r.execute('INSERT OR IGNORE INTO blocks VALUES(?,?)',(uid,target)); self.audit('block.created',uid); return {'ok':True}
        if len(parts)==2 and parts[0]=='blocks' and method=='DELETE':
            r.execute('DELETE FROM blocks WHERE user=? AND target=?',(uid,parts[1])); return {'ok':True}
        self.active(u)
        if path=='/profiles' and method=='GET':
            q=data.get('q','')
            if not isinstance(q,str) or len(q)>60: raise ApiError(400,'Pesquisa inválida')
            # No directory of minors/unknown private profiles. Exact approved contacts only.
            users=r.rows('SELECT * FROM users WHERE name LIKE ? LIMIT 50',('%'+q+'%',))
            return {'items':[self.public(v) for v in users if v['id']!=uid and self.visible(u,v)]}
        if path=='/contacts' and method=='GET': return {'items':r.rows('SELECT c.target AS id,u.name,c.approved FROM contacts c JOIN users u ON u.id=c.target WHERE c.user=?',(uid,))}
        if path=='/contacts' and method=='POST':
            target=text(data,'target'); other=r.one('SELECT * FROM users WHERE id=?',(target,))
            if not other or target==uid or self.blocked(uid,target): raise ApiError(404,'Perfil indisponível')
            self.active(other)
            r.execute('INSERT OR IGNORE INTO contacts VALUES(?,?,0)',(uid,target)); self.notification(target,'Você recebeu um pedido de contato.'); return {'status':'pending'}
        if path=='/contacts/approve' and method=='POST':
            target=text(data,'target'); request=r.one('SELECT * FROM contacts WHERE user=? AND target=?',(target,uid))
            if not request or self.blocked(uid,target): raise ApiError(404,'Pedido indisponível')
            # A minor cannot approve contact without a verified guardian policy/provider.
            if age(u['birth'])<18: raise ApiError(403,'Aprovação pelo responsável ainda não configurada')
            r.execute('UPDATE contacts SET approved=1 WHERE user=? AND target=?',(target,uid))
            r.execute('INSERT OR REPLACE INTO contacts VALUES(?,?,1)',(uid,target)); return {'ok':True}
        if path=='/contacts/requests' and method=='GET': return {'items':r.rows('SELECT u.id,u.name FROM contacts c JOIN users u ON u.id=c.user WHERE c.target=? AND c.approved=0',(uid,))}
        if path=='/media' and method=='POST':
            mime=text(data,'mime',1,40); encoded=text(data,'data',1,7000000)
            if mime not in ('image/jpeg','image/png','image/webp'): raise ApiError(400,'Somente JPEG, PNG e WebP nesta versão')
            try: content=base64.b64decode(encoded,validate=True)
            except ValueError: raise ApiError(400,'Arquivo inválido')
            signatures={'image/jpeg':content.startswith(b'\xff\xd8\xff'),'image/png':content.startswith(b'\x89PNG\r\n\x1a\n'),'image/webp':content.startswith(b'RIFF') and content[8:12]==b'WEBP'}
            if len(content)>5*1024*1024 or not signatures[mime]: raise ApiError(400,'Formato ou tamanho inválido')
            mid=token(); r.execute('INSERT INTO media VALUES(?,?,?,?)',(mid,uid,mime,content)); return {'id':mid}
        if len(parts)==2 and parts[0]=='media' and method=='GET':
            m=r.one('SELECT * FROM media WHERE id=?',(parts[1],))
            if not m: raise ApiError(404,'Imagem indisponível')
            if m['user']!=uid:
                posts=r.rows('SELECT id FROM posts WHERE media=?',(m['id'],))
                if not any(self._can_post(u,p['id']) for p in posts): raise ApiError(404,'Imagem indisponível')
            return {'mime':m['mime'],'data':base64.b64encode(m['data']).decode()}
        if path in ('/posts','/stories'):
            story=int(path=='/stories')
            if method=='POST':
                body=text(data,'text',1,2000); mid=data.get('media')
                if mid and not r.one('SELECT id FROM media WHERE id=? AND user=?',(mid,uid)): raise ApiError(400,'Imagem inválida')
                pid=token(); now=time.time(); r.execute('INSERT INTO posts VALUES(?,?,?,?,?,?,?)',(pid,uid,body,mid,story,now,now+86400 if story else None))
                return {'id':pid}
            if method=='GET':
                try: cursor=float(data.get('cursor',time.time()+1)); limit=min(30,max(1,int(data.get('limit',15))))
                except (TypeError,ValueError): raise ApiError(400,'Paginação inválida')
                rows=r.rows('SELECT * FROM posts WHERE story=? AND created<? AND (expires IS NULL OR expires>?) ORDER BY created DESC',(story,cursor,time.time()))
                visible=[p for p in rows if self._can_post(u,p['id'])]
                page=visible[:limit]
                for p in page:
                    p['author']=self.public(r.one('SELECT * FROM users WHERE id=?',(p['user'],)))
                    p['likes']=r.one('SELECT count(*) AS n FROM likes WHERE post=?',(p['id'],))['n']
                    p['liked']=bool(r.one('SELECT 1 FROM likes WHERE user=? AND post=?',(uid,p['id'])))
                return {'items':page,'nextCursor':page[-1]['created'] if len(visible)>limit else None}
        if len(parts)>=2 and parts[0]=='posts':
            p=self.post(u,parts[1]); pid=p['id']
            if len(parts)==2 and method in ('PATCH','DELETE'):
                if p['user']!=uid: raise ApiError(403,'Você só pode alterar suas publicações')
                if method=='DELETE': r.execute('DELETE FROM posts WHERE id=?',(pid,))
                else: r.execute('UPDATE posts SET text=? WHERE id=?',(text(data,'text'),pid))
                return {'ok':True}
            if len(parts)==3 and parts[2]=='like' and method=='POST':
                if r.one('SELECT 1 FROM likes WHERE user=? AND post=?',(uid,pid)): r.execute('DELETE FROM likes WHERE user=? AND post=?',(uid,pid))
                else: r.execute('INSERT INTO likes VALUES(?,?)',(uid,pid))
                return {'ok':True}
            if len(parts)==3 and parts[2]=='comments':
                if method=='GET': return {'items':r.rows('SELECT c.id,c.text,u.name FROM comments c JOIN users u ON u.id=c.user WHERE c.post=? AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.user=? AND b.target=c.user) OR (b.target=? AND b.user=c.user)) ORDER BY c.created',(pid,uid,uid))}
                if method=='POST':
                    cid=token(); r.execute('INSERT INTO comments VALUES(?,?,?,?,?)',(cid,uid,pid,text(data,'text',1,500),time.time())); return {'id':cid}
        if path=='/conversations' and method=='GET':
            rows=r.rows('SELECT DISTINCT CASE WHEN sender=? THEN recipient ELSE sender END AS id FROM messages WHERE sender=? OR recipient=?',(uid,uid,uid))
            return {'items':[self.public(r.one('SELECT * FROM users WHERE id=?',(v['id'],))) for v in rows if not self.blocked(uid,v['id'])]}
        if len(parts)==2 and parts[0]=='messages':
            target=parts[1]; other=r.one('SELECT * FROM users WHERE id=?',(target,))
            if not other or self.blocked(uid,target) or not self.contact(uid,target): raise ApiError(403,'Mensagens exigem um contato aprovado')
            self.active(other)
            if method=='GET':
                r.execute('UPDATE messages SET read=1 WHERE sender=? AND recipient=?',(target,uid))
                return {'items':r.rows('SELECT * FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?) ORDER BY created LIMIT 200',(uid,target,target,uid))}
            if method=='POST':
                if not u['messages'] or not other['messages']: raise ApiError(403,'Mensagens desativadas nas preferências')
                self.limit(('messages',uid),15)
                mid=token(); r.execute('INSERT INTO messages(id,sender,recipient,text,created) VALUES(?,?,?,?,?)',(mid,uid,target,text(data,'text',1,1000),time.time()))
                self.notification(target,'Nova mensagem de um contato aprovado.'); return {'id':mid,'status':'sent'}
        raise ApiError(404,'Recurso não encontrado')
    def _can_post(self,u,pid):
        try: self.post(u,pid); return True
        except ApiError: return False
