"""Application services: resource authorization and social workflows."""
import base64
import sqlite3
import time
from datetime import date
from contacts import Contacts
from pagination import encode_cursor, decode_cursor
from supervision import Supervision, CATEGORIES
from repository import Repository
from security import ApiError, token, digest, password_hash, password_matches, text, email, age, password as validate_password

class Service:
    def __init__(self, repo, development=False, firebase=None, media_quota=100*1024*1024):
        self.repo, self.development = repo, development
        self.firebase = firebase
        self.supervision=Supervision(self)
        self.lock = repo.lock
        self.contacts = Contacts(self)
        self.limits = {}
        self._guardian_checks = {}
        if media_quota<=0: raise ValueError('Media quota must be positive')
        self.media_quota=media_quota
    def audit(self, event, user):
        self.repo.execute('INSERT INTO audit VALUES(?,?,?,?)', (token(),event,digest(user),time.time()))
    def limit(self, key, ceiling=60, window=60):
        now=time.time()
        self.limits={k:v for k,v in self.limits.items() if v[0]>now}
        expires,count=self.limits.get(key,(now+window,0))
        if count >= ceiling: raise ApiError(429,'Muitas tentativas. Aguarde antes de tentar novamente.')
        self.limits[key]=(expires,count+1)
    def user(self, bearer):
        row=self.repo.one('SELECT u.* FROM users u JOIN sessions s ON s.user=u.id WHERE s.access=? AND s.expires>?',(digest(bearer),time.time())) if self.development else None
        if row: return row
        if self.firebase:
            claims=self.firebase.verify(bearer)
            if self.repo.one('SELECT 1 FROM identity_deletions WHERE uid=?',(claims['uid'],)):
                raise ApiError(401,'Sessão encerrada. Esta conta foi excluída.')
            row=self.repo.one('SELECT u.* FROM users u JOIN firebase_identities f ON f.user=u.id WHERE f.uid=?',(claims['uid'],))
            if not row: raise ApiError(409,'Conclua seu cadastro no aplicativo.')
            verified=int(claims.get('email_verified') is True)
            self.repo.execute('UPDATE users SET verified=? WHERE id=?',(verified,row['id']))
            row['verified']=verified
            return row
        raise ApiError(401,'Sessão expirada. Entre novamente.')
    def guardian_link(self,u):
        return self.repo.one('SELECT l.*,g.name AS guardian_name,g.verified AS guardian_verified,g.birth AS guardian_birth FROM guardian_links l JOIN users g ON g.id=l.guardian WHERE l.child=?',(u['id'],))
    def suspended(self,uid):
        return bool(self.repo.one("SELECT 1 FROM account_status WHERE user=? AND status='suspended'",(uid,)))
    def approved(self,u):
        if age(u['birth'])>=18: return True
        link=self.guardian_link(u)
        if not link or link['state']!='active' or age(link['guardian_birth'])<18: return False
        if self.suspended(link['guardian']): return False
        identity=self.repo.one('SELECT uid FROM firebase_identities WHERE user=?',(link['guardian'],))
        if self.firebase and identity and hasattr(self.firebase,'verified_email'):
            guardian_uid=identity['uid']
            if guardian_uid not in self._guardian_checks:
                self._guardian_checks[guardian_uid]=self.firebase.verified_email(guardian_uid)
            verified=self._guardian_checks[guardian_uid]
            self.repo.execute('UPDATE users SET verified=? WHERE id=?',(int(verified),link['guardian']))
            return verified
        return bool(link['guardian_verified'])
    def nickname_pending(self,u):
        link=self.guardian_link(u) if age(u['birth'])<18 else None
        return bool(link and not link['nickname_selected'])
    def active(self,u):
        if self.suspended(u['id']): raise ApiError(403,'Esta conta está suspensa. Consulte a situação em Privacidade e segurança.','account_suspended')
        if not u['verified'] or not self.approved(u):
            raise ApiError(403,'Confirme os e-mails do menor e do responsável e mantenha o vínculo ativo.')
        if self.nickname_pending(u): raise ApiError(403,'Escolha seu apelido para entrar no feed.')
    def public(self,u,own=False):
        result={k:u[k] for k in ('id','name','bio','private')}
        avatar=self.repo.one('SELECT media FROM profile_media WHERE user=?',(u['id'],))
        result['avatar']=avatar['media'] if avatar else None
        if own: result.update({k:u[k] for k in ('email','verified','messages')},approved=int(self.approved(u)),needsGuardian=age(u['birth'])<18,needsNickname=self.nickname_pending(u),isAdmin=self.development and bool(self.repo.one('SELECT 1 FROM administrators WHERE user=?',(u['id'],))))
        if own: result['accountStatus']='suspended' if self.suspended(u['id']) else 'active'
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
        today=date.today()
        return bool(self.repo.one('''SELECT 1 FROM contacts c WHERE c.user=? AND c.target=? AND c.approved=1
            AND NOT EXISTS(SELECT 1 FROM users child WHERE child.id IN(c.user,c.target)
                AND (? - cast(substr(child.birth,1,4) AS INTEGER) - (? < substr(child.birth,6,5)))<18
                AND NOT EXISTS(SELECT 1 FROM contact_requests q JOIN contact_consents consent ON consent.request=q.id
                    JOIN guardian_links link ON link.child=consent.child AND link.guardian=consent.guardian
                    WHERE q.status='approved' AND q.accepted=1 AND consent.approved=1 AND link.state='active'
                    AND consent.child=child.id AND ((q.source=c.user AND q.target=c.target) OR (q.source=c.target AND q.target=c.user))))''',
            (a,b,today.year,today.strftime('%m-%d'))))
    def visible(self,u,owner):
        if u['id']==owner['id']: return True
        if self.suspended(owner['id']): return False
        if self.blocked(u['id'],owner['id']): return False
        if not owner['verified'] or not self.approved(owner) or self.nickname_pending(owner): return False
        return not owner['private'] or self.contact(u['id'],owner['id'])
    def post(self,u,pid):
        p=self.repo.one('SELECT * FROM posts WHERE id=?',(pid,))
        if not p or (p['expires'] and p['expires']<=time.time()): raise ApiError(404,'Publicação indisponível')
        owner=self.repo.one('SELECT * FROM users WHERE id=?',(p['user'],))
        if not self.visible(u,owner): raise ApiError(404,'Publicação indisponível')
        return p
    def notification(self,user,message):
        self.repo.execute('INSERT INTO notifications VALUES(?,?,?,?)',(token(),user,message,time.time()))
    def dispatch(self,method,path,data,bearer='',ip='local',idempotency_key=None):
        with self.lock:
            self.limit(('ip',ip),180)
            self._guardian_checks = {}
            with self.repo.transaction():
                if idempotency_key is not None:
                    from mutations import supported, execute
                    if not supported(method,path): raise ApiError(400,'Esta operação não aceita identificador de repetição.')
                    actor=self.user(bearer)
                    result=execute(self,actor,method,path,data,idempotency_key,lambda:self._dispatch(method,path,data,bearer,ip,actor))
                else:
                    result=self._dispatch(method,path,data,bearer,ip)
            # Remote deletion follows the durable local commit and can be retried.
            if method=='DELETE' and path=='/me': self.process_identity_deletions()
            return result

    def process_identity_deletions(self):
        if not self.firebase: return
        with self.lock:
            jobs=self.repo.rows('SELECT * FROM identity_deletions WHERE completed IS NULL AND next_attempt<=? ORDER BY created LIMIT 10',(time.time(),))
            for job in jobs:
                try:
                    self.firebase.delete(job['uid'])
                except Exception:
                    delay=min(3600,30*2**min(job['attempts'],7))
                    self.repo.execute('UPDATE identity_deletions SET attempts=attempts+1,next_attempt=? WHERE uid=?',(time.time()+delay,job['uid']))
                else:
                    self.repo.execute('UPDATE identity_deletions SET completed=? WHERE uid=?',(time.time(),job['uid']))
    def _dispatch(self,method,path,data,bearer,ip,actor=None):
        r=self.repo
        parts=path.strip('/').split('/')
        if path=='/health': return {'status':'ok','storage':'sqlite','development':self.development,'firebase':self.firebase is not None,'familyFlow':True}
        if path.startswith('/auth/'):
            if not self.development and path not in ('/auth/firebase','/auth/logout'):
                raise ApiError(404,'Recurso indisponivel.')
            self.limit(('auth',ip),30)
            if path=='/auth/firebase' and method=='POST':
                if not self.firebase: raise ApiError(503,'Configure Firebase Admin na API antes de usar o login Firebase.')
                claims=self.firebase.verify(bearer)
                firebase_uid=claims['uid']; mail=email({'email':claims.get('email')})
                if r.one('SELECT 1 FROM identity_deletions WHERE uid=?',(firebase_uid,)):
                    raise ApiError(401,'Esta conta foi excluída. Crie uma nova conta para voltar.')
                existing=r.one('SELECT user FROM firebase_identities WHERE uid=?',(firebase_uid,))
                if not existing:
                    # Never merge accounts by email: possession of a Firebase identity
                    # does not prove ownership of an existing local Conexia account.
                    if r.one('SELECT id FROM users WHERE email=?',(mail,)):
                        raise ApiError(409,'Este e-mail pertence a uma conta local anterior. Use outro e-mail para testar o Firebase; a migração ainda precisa ser feita.')
                    name=text(data,'name',1,60); birth=text(data,'birth',10,10); years=age(birth)
                    if years<18: raise ApiError(403,'A conta do menor deve ser criada ou vinculada pelo perfil do responsável.')
                    guardian=None
                    if guardian==mail: raise ApiError(400,'Use um e-mail independente do responsável')
                    uid=token()
                    with r.transaction():
                        r.db.execute('INSERT INTO users(id,email,password,name,birth,guardian,verified) VALUES(?,?,?,?,?,?,?)',(uid,mail,password_hash(token()),name,birth,guardian,int(claims.get('email_verified') is True)))
                        r.db.execute('INSERT INTO firebase_identities VALUES(?,?)',(firebase_uid,uid))
                    self.audit('account.firebase.created',uid)
                return {'user':self.public(self.user(bearer),True)}
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
                result=self.challenge(u,'reset') if u and not r.one('SELECT uid FROM firebase_identities WHERE user=?',(u['id'],)) else {}
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
        u=actor or self.user(bearer); uid=u['id']
        if self.suspended(uid) and path not in ('/me','/me/export','/auth/logout','/reports','/blocks') and not path.startswith('/blocks/'):
            self.active(u)
        if path=='/admin' or path.startswith('/admin/'):
            from administration import dispatch_admin
            return dispatch_admin(self,u,method,path,data)
        if path=='/auth/logout' and method=='POST':
            identity=r.one('SELECT uid FROM firebase_identities WHERE user=?',(uid,))
            if identity: self.firebase.revoke(identity['uid'])
            r.execute('DELETE FROM sessions WHERE access=?',(digest(bearer),)); return {'ok':True}
        if path=='/me' and method=='GET': return self.public(u,True)
        if path=='/me' and method=='PATCH':
            name=text(data,'name',1,60) if 'name' in data else u['name']; bio=data.get('bio',u['bio'])
            if not isinstance(bio,str) or len(bio)>180: raise ApiError(400,'Biografia muito longa')
            private=data.get('private',bool(u['private'])); messages=data.get('messages',bool(u['messages']))
            if not isinstance(private,bool) or not isinstance(messages,bool): raise ApiError(400,'Preferências inválidas')
            if age(u['birth'])<18 and not private: raise ApiError(403,'Perfis de menores permanecem privados')
            r.execute('UPDATE users SET name=?,bio=?,private=?,messages=? WHERE id=?',(name,bio,int(private),int(messages),uid))
            if age(u['birth'])<18 and 'name' in data: r.execute('UPDATE guardian_links SET nickname_selected=1 WHERE child=?',(uid,))
            return self.public(r.one('SELECT * FROM users WHERE id=?',(uid,)),True)
        if path=='/me/export' and method=='GET':
            result={'profile':dict(self.public(u,True),birth=u['birth'])}
            for table,field in [('posts','user'),('comments','user'),('reports','user'),('blocks','user')]: result[table]=r.rows(f'SELECT * FROM {table} WHERE {field}=?',(uid,))
            result['messages']=r.rows('SELECT * FROM messages WHERE sender=? OR recipient=?',(uid,uid))
            result['likes']=r.rows('SELECT post FROM likes WHERE user=?',(uid,))
            result['contacts']=r.rows('SELECT target,approved FROM contacts WHERE user=?',(uid,))
            result['notifications']=r.rows('SELECT id,text,created FROM notifications WHERE user=?',(uid,))
            result['media']=r.rows('SELECT id,mime,length(data) bytes FROM media WHERE user=?',(uid,))
            result['contactRequests']=r.rows('SELECT id,source,target,accepted,status,created,expires FROM contact_requests WHERE source=? OR target=?',(uid,uid))
            # Export only this user's actions, without exposing another family's private names.
            result['consents']=r.rows('SELECT request,child,approved FROM contact_consents WHERE guardian=? OR child=?',(uid,uid))
            return result
        if path=='/me' and method=='DELETE':
            identity=r.one('SELECT uid FROM firebase_identities WHERE user=?',(uid,))
            if identity:
                claims=self.firebase.verify(bearer)
                authenticated=claims.get('auth_time',0)
                if claims['uid']!=identity['uid'] or not isinstance(authenticated,(float,int)) or not 0<=time.time()-authenticated<=300:
                    raise ApiError(401,'Confirme sua senha novamente antes de excluir a conta.','reauthentication_required')
                r.execute('INSERT INTO identity_deletions(uid,created) VALUES(?,?)',(identity['uid'],time.time()))
                self.audit('account.deleted',uid); r.execute('DELETE FROM users WHERE id=?',(uid,)); return {'ok':True}
            pw=data.get('password','')
            if not isinstance(pw,str) or len(pw)>128: raise ApiError(400,'Senha inválida')
            if not password_matches(pw,u['password']): raise ApiError(401,'Senha incorreta','reauthentication_required')
            self.audit('account.deleted',uid); r.execute('DELETE FROM users WHERE id=?',(uid,)); return {'ok':True}
        if path=='/guardian/status' and method=='GET':
            approved=self.approved(u)
            link=self.guardian_link(u)
            return {'required':age(u['birth'])<18,'approved':approved,'childVerified':bool(u['verified']),'guardianVerified':bool(link and link['guardian_verified']),'guardianName':link['guardian_name'] if link else None,'state':link['state'] if link else 'unlinked','needsNickname':self.nickname_pending(u)}
        if path=='/guardian/request' and method=='POST':
            return {'message':'Entre na conta do responsável, confirme o e-mail e use o painel para criar ou vincular o perfil do menor.'}
        if path=='/guardian/children':
            if age(u['birth'])<18 or not u['verified']: raise ApiError(403,'Use uma conta adulta com e-mail confirmado.')
            if method=='GET':
                children=r.rows('SELECT c.*,l.child_name,l.nickname_selected,l.state FROM guardian_links l JOIN users c ON c.id=l.child WHERE l.guardian=? ORDER BY l.created',(uid,))
                return {'items':[dict(self.public(c,True),childName=c['child_name'],state=c['state']) for c in children]}
            if method=='POST':
                if not self.firebase: raise ApiError(503,'Configure Firebase para criar o perfil do menor.')
                guardian_identity=r.one('SELECT uid FROM firebase_identities WHERE user=?',(uid,))
                if not guardian_identity: raise ApiError(403,'O responsável precisa usar uma conta Firebase com e-mail confirmado.')
                if hasattr(self.firebase,'verified_email') and not self.firebase.verified_email(guardian_identity['uid']): raise ApiError(403,'Confirme o e-mail do responsável antes de criar o perfil do menor.')
                if data.get('consent') is not True: raise ApiError(400,'Confirme a autorização do vínculo.')
                claims=self.firebase.verify(text(data,'childToken',1,10000))
                mail=email({'email':claims.get('email')}); child_uid=claims['uid']
                if mail==u['email']: raise ApiError(400,'O menor precisa de um e-mail diferente do responsável.')
                name=text(data,'name',1,60); birth=text(data,'birth',10,10)
                if age(birth)>=18: raise ApiError(400,'Este fluxo é destinado a perfis de menores.')
                existing=r.one('SELECT c.* FROM firebase_identities f JOIN users c ON c.id=f.user WHERE f.uid=?',(child_uid,))
                if existing:
                    if age(existing['birth'])>=18: raise ApiError(400,'Este perfil já é adulto.')
                    link=self.guardian_link(existing)
                    if link and link['guardian']!=uid: raise ApiError(409,'Este perfil já está vinculado a outro responsável.')
                    if not link and existing['guardian']!=u['email']: raise ApiError(403,'O e-mail do responsável não corresponde ao cadastro anterior.')
                    cid=existing['id']
                    if not link: r.execute('INSERT INTO guardian_links VALUES(?,?,?,?,?,?)',(cid,uid,name,1,'active',time.time()))
                    r.execute('UPDATE users SET verified=? WHERE id=?',(int(claims.get('email_verified') is True),cid))
                else:
                    if r.one('SELECT id FROM users WHERE email=?',(mail,)): raise ApiError(409,'Este e-mail pertence a um cadastro anterior que precisa de migração.')
                    cid=token()
                    with r.transaction():
                        r.db.execute('INSERT INTO users(id,email,password,name,birth,guardian,verified) VALUES(?,?,?,?,?,?,?)',(cid,mail,password_hash(token()),'Novo perfil',birth,u['email'],int(claims.get('email_verified') is True)))
                        r.db.execute('INSERT INTO firebase_identities VALUES(?,?)',(child_uid,cid))
                        r.db.execute('INSERT INTO guardian_links VALUES(?,?,?,?,?,?)',(cid,uid,name,0,'active',time.time()))
                    self.audit('guardian.child.created',uid)
                return {'user':self.public(r.one('SELECT * FROM users WHERE id=?',(cid,)),True)}
        if len(parts)==3 and parts[:2]==['guardian','children'] and method=='PATCH':
            if age(u['birth'])<18 or not u['verified']: raise ApiError(403,'Use uma conta adulta verificada.')
            link=r.one('SELECT * FROM guardian_links WHERE child=? AND guardian=?',(parts[2],uid))
            if not link: raise ApiError(404,'Vínculo indisponível.')
            state=data.get('state')
            if state not in ('active','paused'): raise ApiError(400,'Situação inválida.')
            r.execute('UPDATE guardian_links SET state=? WHERE child=?',(state,parts[2])); self.audit('guardian.link.'+state,uid)
            return {'ok':True}
        if path=='/me/avatar' and method in ('POST','DELETE'):
            self.active(u)
            previous=r.one('SELECT media FROM profile_media WHERE user=?',(uid,))
            if method=='POST':
                mid=text(data,'media',1,200)
                if not r.one('SELECT id FROM media WHERE id=? AND user=?',(mid,uid)): raise ApiError(400,'Foto inválida ou de outra conta.')
                r.execute('INSERT OR REPLACE INTO profile_media VALUES(?,?)',(uid,mid))
            else: r.execute('DELETE FROM profile_media WHERE user=?',(uid,))
            if previous:
                r.execute('DELETE FROM media WHERE id=? AND NOT EXISTS(SELECT 1 FROM profile_media WHERE media=?) AND NOT EXISTS(SELECT 1 FROM posts WHERE media=?) AND NOT EXISTS(SELECT 1 FROM post_media WHERE media=?)',(previous['media'],)*4)
            return self.public(r.one('SELECT * FROM users WHERE id=?',(uid,)),True)
        if len(parts)==6 and parts[:3]==['family','activity','posts'] and parts[4]=='media' and method=='GET': return self.supervision.media(u,None,parts[3],parts[5])
        if path=='/family/activity' and method=='GET': return self.supervision.activity(u,None,data)
        if path=='/family/discussions' and method=='POST': return self.supervision.discuss(u,None,data)
        if len(parts)==3 and parts[:2]==['family','discussions'] and method=='PATCH': return self.supervision.resolve(u,parts[2],data)
        if len(parts)>=4 and parts[:2]==['guardian','children']:
            child_id=parts[2]
            if len(parts)==4 and parts[3]=='contacts' and method=='GET': return self.contacts.family_list(u,child_id)
            if len(parts)==5 and parts[3]=='contacts' and method=='PATCH': return self.contacts.decide(u,child_id,parts[4],data)
            if len(parts)==4 and parts[3]=='activity' and method=='GET': return self.supervision.activity(u,child_id,data)
            if len(parts)==4 and parts[3]=='discussions' and method=='POST': return self.supervision.discuss(u,child_id,data)
            if len(parts)==8 and parts[3:5]==['activity','posts'] and parts[6]=='media' and method=='GET': return self.supervision.media(u,child_id,parts[5],parts[7])
        if path=='/notifications' and method=='GET': return {'items':r.rows('SELECT id,text,created FROM notifications WHERE user=? ORDER BY created DESC LIMIT 50',(uid,))}
        if path=='/reports' and method=='GET': return {'items':r.rows('SELECT * FROM reports WHERE user=? ORDER BY created DESC',(uid,))}
        if path=='/reports' and method=='POST':
            self.limit(('reports',uid),10,3600)
            reason=text(data,'reason',3,1000); target=text(data,'target',1,200); rid=token()
            r.execute('INSERT INTO reports(id,user,target,reason,created) VALUES(?,?,?,?,?)',(rid,uid,target,reason,time.time()))
            self.audit('report.created',uid); return {'id':rid,'status':'pending','message':'Registrada. Atendimento humano ainda precisa ser configurado.'}
        if path=='/blocks' and method=='GET': return {'items':r.rows('SELECT u.id,u.name FROM users u JOIN blocks b ON b.target=u.id WHERE b.user=?',(uid,))}
        if path=='/blocks' and method=='POST':
            target=text(data,'target')
            if target==uid or not r.one('SELECT id FROM users WHERE id=?',(target,)): raise ApiError(400,'Perfil inválido')
            self.contacts.disconnect(uid,target)
            r.execute('INSERT OR IGNORE INTO blocks VALUES(?,?)',(uid,target)); self.audit('block.created',uid); return {'ok':True}
        if len(parts)==2 and parts[0]=='blocks' and method=='DELETE':
            r.execute('DELETE FROM blocks WHERE user=? AND target=?',(uid,parts[1])); return {'ok':True}
        self.active(u)
        if len(parts)==2 and parts[0]=='profiles' and method=='GET':
            other=r.one('SELECT * FROM users WHERE id=?',(parts[1],))
            if not other or not self.visible(u,other): raise ApiError(404,'Perfil indisponível')
            return self.public(other)
        if path=='/profiles' and method=='GET':
            q=data.get('q','')
            if not isinstance(q,str) or len(q)>60: raise ApiError(400,'Pesquisa inválida')
            # No directory of minors/unknown private profiles. Exact approved contacts only.
            items=[];after=''
            while len(items)<50:
                users=r.rows('SELECT * FROM users WHERE name LIKE ? AND id>? AND id!=? AND verified=1 ORDER BY id LIMIT 100',('%'+q+'%',after,uid))
                if not users:break
                for candidate in users:
                    if self.visible(u,candidate):items.append(self.public(candidate))
                    if len(items)==50:break
                after=users[-1]['id']
            return {'items':items}
        if path=='/contacts' and method=='GET':
            rows=r.rows('SELECT c.target AS id,u.name,c.approved FROM contacts c JOIN users u ON u.id=c.target WHERE c.user=?',(uid,))
            return {'items':[row for row in rows if not self.blocked(uid,row['id']) and (
                self.contact(uid,row['id']) if row['approved'] else r.one("SELECT 1 FROM contact_requests WHERE source=? AND target=? AND status='pending' AND expires>?",(uid,row['id'],time.time())))]}

        if path=='/contacts' and method=='POST':
            return self.contacts.create(u,text(data,'target',1,200))
        if path=='/contacts/approve' and method=='POST':
            return self.contacts.accept(u,text(data,'target',1,200))
        if path=='/contacts/requests' and method=='GET':
            return self.contacts.requests(u)
        if len(parts)==3 and parts[:2]==['contacts','requests'] and method=='DELETE':
            return self.contacts.cancel(u,parts[2])
        if len(parts)==2 and parts[0]=='contacts' and method=='DELETE':
            self.contacts.disconnect(uid,parts[1]); return {'ok':True}
        if path=='/media' and method=='POST':
            self.limit(('uploads',uid),40,3600)
            from images import normalize
            mime,content=normalize(data)
            used=r.one('SELECT coalesce(sum(length(data)),0) n FROM media WHERE user=?',(uid,))['n']
            if used+len(content)>self.media_quota: raise ApiError(413,'Limite de armazenamento da conta atingido.')
            mid=token(); r.execute('INSERT INTO media VALUES(?,?,?,?)',(mid,uid,mime,content)); return {'id':mid}
        if len(parts)==2 and parts[0]=='media' and method=='GET':
            m=r.one('SELECT * FROM media WHERE id=?',(parts[1],))
            if not m: raise ApiError(404,'Imagem indisponível')
            if m['user']!=uid:
                posts=r.rows('SELECT DISTINCT p.id FROM posts p LEFT JOIN post_media pm ON pm.post=p.id WHERE p.media=? OR pm.media=?',(m['id'],m['id']))
                profile=r.one('SELECT u.* FROM profile_media pm JOIN users u ON u.id=pm.user WHERE pm.media=?',(m['id'],))
                if not (profile and self.visible(u,profile)) and not any(self._can_post(u,p['id']) for p in posts): raise ApiError(404,'Imagem indisponível')
            return {'mime':m['mime'],'data':base64.b64encode(m['data']).decode()}
        if path in ('/posts','/stories'):
            story=int(path=='/stories')
            if method=='POST':
                self.limit(('publications',uid),30,60)
                body=text(data,'text',1,2000)
                category=data.get('category','other')
                if not isinstance(category,str) or category not in CATEGORIES: raise ApiError(400,'Categoria inválida.')
                media_items=data.get('mediaItems', [data['media']] if data.get('media') else [])
                if not isinstance(media_items,list) or len(media_items)>10 or any(not isinstance(mid,str) for mid in media_items): raise ApiError(400,'Use até 10 imagens válidas')
                if len(set(media_items))!=len(media_items): raise ApiError(400,'Imagens duplicadas')
                for mid in media_items:
                    if not r.one('SELECT id FROM media WHERE id=? AND user=?',(mid,uid)): raise ApiError(400,'Imagem inválida')
                pid=token(); now=time.time()
                # The post and gallery are one transaction; old single-photo readers keep working.
                with r.transaction():
                    r.db.execute('INSERT INTO posts VALUES(?,?,?,?,?,?,?)',(pid,uid,body,media_items[0] if media_items else None,story,now,now+86400 if story else None))
                    r.db.executemany('INSERT INTO post_media VALUES(?,?,?)',[(pid,mid,i) for i,mid in enumerate(media_items)])
                    r.db.execute('INSERT INTO post_categories VALUES(?,?)',(pid,category))
                return {'id':pid}
            if method=='GET':
                try: limit=min(30,max(1,int(data.get('limit',15))))
                except (TypeError,ValueError): raise ApiError(400,'Paginação inválida')
                cursor,after_id=decode_cursor(data.get('cursor'),time.time()+1)
                author=data.get('user')
                if author is not None:
                    if not isinstance(author,str) or len(author)>200:raise ApiError(400,'Perfil inválido')
                    owner=r.one('SELECT * FROM users WHERE id=?',(author,))
                    if not owner or not self.visible(u,owner): raise ApiError(404,'Perfil indisponível')
                visible=[];owners={};permissions={};now=time.time()
                while len(visible)<=limit:
                    sql='''SELECT p.* FROM posts p JOIN users o ON o.id=p.user
                        WHERE p.story=? AND (p.created<? OR (p.created=? AND p.id<?))
                        AND (p.expires IS NULL OR p.expires>?)
                        AND (p.user=? OR (o.verified=1 AND (o.private=0 OR EXISTS(
                            SELECT 1 FROM contacts c WHERE c.user=? AND c.target=p.user AND c.approved=1))
                            AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.user=? AND b.target=p.user) OR (b.target=? AND b.user=p.user))))'''
                    args=[story,cursor,cursor,after_id,now,uid,uid,uid,uid]
                    if author is not None:sql+=' AND p.user=?';args.append(author)
                    rows=r.rows(sql+' ORDER BY p.created DESC,p.id DESC LIMIT 64',args)
                    if not rows:break
                    for post in rows:
                        owner_id=post['user']
                        if owner_id not in permissions:
                            owners[owner_id]=r.one('SELECT * FROM users WHERE id=?',(owner_id,))
                            permissions[owner_id]=self.visible(u,owners[owner_id])
                        if permissions[owner_id]:visible.append(post)
                        if len(visible)>limit:break
                    cursor,after_id=rows[-1]['created'],rows[-1]['id']
                page=visible[:limit];ids=[p['id'] for p in page]
                images={};categories={};likes={};authors={}
                if ids:
                    slots=','.join('?' for _ in ids)
                    for image in r.rows(f'SELECT post,media FROM post_media WHERE post IN ({slots}) ORDER BY post,position',ids):
                        images.setdefault(image['post'],[]).append(image['media'])
                    categories={v['post']:v['category'] for v in r.rows(f'SELECT post,category FROM post_categories WHERE post IN ({slots})',ids)}
                    likes={v['post']:v for v in r.rows(f'SELECT post,count(*) n,max(CASE WHEN user=? THEN 1 ELSE 0 END) liked FROM likes WHERE post IN ({slots}) GROUP BY post',[uid,*ids])}
                for p in page:
                    p['mediaItems']=images.get(p['id']) or ([p['media']] if p['media'] else [])
                    p['category']=categories.get(p['id'],'other')
                    if p['user'] not in authors:authors[p['user']]=self.public(owners[p['user']])
                    p['author']=authors[p['user']]
                    p['likes']=likes.get(p['id'],{}).get('n',0)
                    p['liked']=bool(likes.get(p['id'],{}).get('liked',0))
                return {'items':page,'nextCursor':encode_cursor(page[-1]['created'],page[-1]['id']) if len(visible)>limit else None}
        if len(parts)>=2 and parts[0]=='posts':
            p=self.post(u,parts[1]); pid=p['id']
            if len(parts)==3 and parts[2]=='view' and method=='POST': return self.supervision.record(u,pid,data)
            if len(parts)==2 and method in ('PATCH','DELETE'):
                if p['user']!=uid: raise ApiError(403,'Você só pode alterar suas publicações')
                if method=='DELETE': r.execute('DELETE FROM posts WHERE id=?',(pid,))
                else: r.execute('UPDATE posts SET text=? WHERE id=?',(text(data,'text',1,2000),pid))
                return {'ok':True}
            if len(parts)==3 and parts[2]=='like' and method=='POST':
                previous=bool(r.one('SELECT 1 FROM likes WHERE user=? AND post=?',(uid,pid)))
                desired=data.get('liked',not previous)
                if not isinstance(desired,bool):raise ApiError(400,'Curtida inválida')
                if desired:r.execute('INSERT OR IGNORE INTO likes VALUES(?,?)',(uid,pid))
                else:r.execute('DELETE FROM likes WHERE user=? AND post=?',(uid,pid))
                return {'ok':True,'liked':desired,'likes':r.one('SELECT count(*) n FROM likes WHERE post=?',(pid,))['n']}
            if len(parts)==3 and parts[2]=='comments':
                if method=='GET': return {'items':r.rows('SELECT c.id,c.text,u.name FROM comments c JOIN users u ON u.id=c.user WHERE c.post=? AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.user=? AND b.target=c.user) OR (b.target=? AND b.user=c.user)) ORDER BY c.created',(pid,uid,uid))}
                if method=='POST':
                    self.limit(('comments',uid),30,60)
                    cid=token(); r.execute('INSERT INTO comments VALUES(?,?,?,?,?)',(cid,uid,pid,text(data,'text',1,500),time.time())); return {'id':cid}
        if path=='/conversations' and method=='GET':
            rows=r.rows('SELECT DISTINCT CASE WHEN sender=? THEN recipient ELSE sender END AS id FROM messages WHERE sender=? OR recipient=?',(uid,uid,uid))
            return {'items':[self.public(r.one('SELECT * FROM users WHERE id=?',(v['id'],))) for v in rows if not self.blocked(uid,v['id'])]}
        if len(parts) in (2,3) and parts[0]=='messages':
            target=parts[1]; other=r.one('SELECT * FROM users WHERE id=?',(target,))
            if not other or self.blocked(uid,target) or not self.contact(uid,target): raise ApiError(403,'Mensagens exigem um contato aprovado')
            self.active(other)
            if len(parts)==3:
                if parts[2]!='read' or method!='POST':raise ApiError(404,'Recurso não encontrado')
                ids=data.get('ids')
                if not isinstance(ids,list) or not 1<=len(ids)<=200 or any(not isinstance(mid,str) for mid in ids) or len(ids)!=len(set(ids)):
                    raise ApiError(400,'Mensagens inválidas')
                slots=','.join('?' for _ in ids)
                owned=r.rows(f'SELECT id FROM messages WHERE sender=? AND recipient=? AND id IN ({slots})',[target,uid,*ids])
                if len(owned)!=len(ids):raise ApiError(400,'Mensagens inválidas')
                r.execute(f'UPDATE messages SET read=1 WHERE sender=? AND recipient=? AND id IN ({slots})',[target,uid,*ids])
                return {'ok':True}
            if method=='GET':
                cursor,after_id=decode_cursor(data.get('cursor'),time.time()+1)
                rows=r.rows('''SELECT * FROM messages WHERE ((sender=? AND recipient=?) OR (sender=? AND recipient=?))
                    AND (created<? OR (created=? AND id<?)) ORDER BY created DESC,id DESC LIMIT 201''',(uid,target,target,uid,cursor,cursor,after_id))
                page=rows[:200]
                return {'items':list(reversed(page)),'nextCursor':encode_cursor(page[-1]['created'],page[-1]['id']) if len(rows)>200 else None}
            if method=='POST':
                if not u['messages'] or not other['messages']: raise ApiError(403,'Mensagens desativadas nas preferências')
                self.limit(('messages',uid),15)
                mid=token(); r.execute('INSERT INTO messages(id,sender,recipient,text,created) VALUES(?,?,?,?,?)',(mid,uid,target,text(data,'text',1,1000),time.time()))
                self.notification(target,'Nova mensagem de um contato aprovado.'); return {'id':mid,'status':'sent'}
        raise ApiError(404,'Recurso não encontrado')
    def _can_post(self,u,pid):
        try: self.post(u,pid); return True
        except ApiError: return False
