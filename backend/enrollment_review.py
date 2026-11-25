"""Human enrollment review, separate from age research and social media."""
import base64
import json
import os
from pathlib import Path
import time
from security import ApiError, age, token, text

VERSION='enrollment-review-v1'
NOTICE='Revisão humana do cadastro: a captura será armazenada temporariamente, criptografada, e poderá ser consultada por administradores autorizados. Não vira foto de perfil. Disponível para análise por até 48 horas; exclusão lógica ao decidir/revogar ou na limpeza periódica em até mais uma hora com a API em execução. Decisão não comprova idade, identidade ou parentesco.'

class ReviewVault:
    def __init__(self,key):
        from cryptography.fernet import Fernet
        self.cipher=Fernet(key)
    @classmethod
    def local(cls,path):
        from cryptography.fernet import Fernet
        path=Path(path).resolve();path.parent.mkdir(parents=True,exist_ok=True)
        if not path.exists():
            try:
                fd=os.open(str(path),os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
                with os.fdopen(fd,'wb') as handle:handle.write(Fernet.generate_key())
            except FileExistsError:pass
        return cls(path.read_bytes().strip())
    def encrypt(self,value):return self.cipher.encrypt(value)
    def decrypt(self,value):return self.cipher.decrypt(value)

def event(s,case,actor,action,reason=''):
    s.repo.execute('INSERT INTO review_events VALUES(?,?,?,?,?,?)',(token(),case,actor,action,reason,time.time()))

def consent(s,child):
    return s.repo.one('''SELECT c.* FROM review_consents c JOIN guardian_links l ON l.child=c.child AND l.guardian=c.guardian
        WHERE c.child=? AND c.granted=1 AND c.version=?''',(child,VERSION))

def current(s,child):
    return s.repo.one('''SELECT c.* FROM enrollment_reviews c JOIN guardian_links l ON l.child=c.child AND l.guardian=c.guardian
        WHERE c.child=? ORDER BY c.created DESC,c.id DESC LIMIT 1''',(child,))

def allowed(s,u):
    if not s.review_required or age(u['birth'])>=18:return True
    c=current(s,u['id'])
    return bool(consent(s,u['id']) and c and c['version']==VERSION and c['state']=='approved')

def status(s,child):
    case=current(s,child)
    authorized=consent(s,child) is not None
    user=s.repo.one('SELECT * FROM users WHERE id=?',(child,))
    return {'required':s.review_required,'authorized':authorized,'consentVersion':VERSION,'notice':NOTICE,
            'checks':{'childEmail':bool(user and user['verified']),'family':bool(user and s.family_approved(user))},
            'state':case['state'] if authorized and case else 'revoked' if case else 'not_submitted',
            'caseId':case['id'] if case else None,'reason':case['reason'] if case else '',
            'updated':case['updated'] if case else None,
            'history':s.repo.rows('SELECT action,reason,created FROM review_events WHERE review=? ORDER BY created DESC LIMIT 100',(case['id'],)) if case else []}

def prerequisites(s,u):
    if age(u['birth'])>=18:raise ApiError(403,'Esta etapa é destinada ao perfil do menor.')
    if s.suspended(u['id']) or not u['verified'] or not s.family_approved(u):
        raise ApiError(403,'Confirme os dois e-mails e mantenha o vínculo familiar ativo.')
    if not consent(s,u['id']):raise ApiError(403,'O responsável precisa autorizar separadamente a revisão do cadastro.')

def reviewer(s,u,case=None):
    s.active(u)
    if age(u['birth'])<18 or not s.development or not s.repo.one('SELECT 1 FROM administrators WHERE user=?',(u['id'],)):
        raise ApiError(403,'Revisão restrita aos administradores autorizados.')
    if case and u['id'] in (case['guardian'],case['child']):raise ApiError(403,'Outro administrador deve revisar este cadastro.')

def purge(s):
    now=time.time();r=s.repo
    rows=r.rows("SELECT c.id FROM enrollment_reviews c JOIN review_photos p ON p.review=c.id WHERE p.expires<=? AND c.state IN ('pending','additional_review')",(now,))
    for c in rows:
        reason='A captura expirou. Envie uma nova foto para continuar a análise.'
        r.execute("UPDATE enrollment_reviews SET state='correction',reason=?,updated=? WHERE id=?",(reason,now,c['id']))
        event(s,c['id'],None,'capture.expired',reason)
    r.execute('DELETE FROM review_photos WHERE expires<=?',(now,))
    r.execute('DELETE FROM review_tickets WHERE expires<=?',(now,))
    r.execute('DELETE FROM review_limits WHERE reset<=?',(now,))

def dispatch_review(s,u,method,path,data):
    r=s.repo;uid=u['id'];parts=path.strip('/').split('/');now=time.time()
    purge(s)
    if path=='/enrollment/status' and method=='GET':return status(s,uid)
    if len(parts)==4 and parts[:2]==['enrollment','children'] and parts[3] in ('status','consent'):
        child=parts[2]
        link=r.one('SELECT * FROM guardian_links WHERE child=? AND guardian=?',(child,uid))
        if not link or age(u['birth'])<18:raise ApiError(404,'Perfil indisponível.')
        if method=='GET':return status(s,child)
        if method=='POST' and parts[3]=='consent':
            s.active(u)
            granted=data.get('granted')
            if not isinstance(granted,bool) or data.get('consentVersion')!=VERSION:raise ApiError(400,'Revise a autorização para armazenamento e análise da captura.')
            r.execute('INSERT INTO review_consents VALUES(?,?,?,?,?) ON CONFLICT(child) DO UPDATE SET guardian=excluded.guardian,granted=excluded.granted,version=excluded.version,updated=excluded.updated',(child,uid,int(granted),VERSION,now))
            r.execute('INSERT INTO review_consent_events VALUES(?,?,?,?,?,?)',(token(),child,uid,int(granted),VERSION,now))
            if not granted:
                for case in r.rows('SELECT id FROM enrollment_reviews WHERE child=?',(child,)):
                    r.execute('DELETE FROM review_photos WHERE review=?',(case['id'],))
                    event(s,case['id'],uid,'consent.revoked')
                r.execute("UPDATE enrollment_reviews SET state='revoked',reason='Autorização revogada. Novo envio depende de nova autorização.',updated=? WHERE child=?",(now,child))
                r.execute('DELETE FROM review_tickets WHERE child=?',(child,))
            return status(s,child)
    if path=='/enrollment/tickets' and method=='POST':
        prerequisites(s,u)
        if not s.review_vault:raise ApiError(503,'Armazenamento privado da revisão ainda não configurado.')
        if data.get('consent') is not True or data.get('consentVersion')!=VERSION:raise ApiError(400,'Leia e aceite o envio para revisão humana.')
        case=current(s,uid)
        if case and case['state']=='approved':raise ApiError(409,'O cadastro já foi aprovado.')
        limit=r.one('SELECT * FROM review_limits WHERE user=?',(uid,))
        if limit and limit['reset']>now and limit['count']>=6:raise ApiError(429,'Limite de seis capturas por hora. Tente mais tarde.')
        if not limit or limit['reset']<=now:r.execute('INSERT INTO review_limits VALUES(?,?,1) ON CONFLICT(user) DO UPDATE SET reset=excluded.reset,count=1',(uid,now+3600))
        else:r.execute('UPDATE review_limits SET count=count+1 WHERE user=?',(uid,))
        r.execute('DELETE FROM review_tickets WHERE child=?',(uid,))
        tid=token();grant=consent(s,uid)
        r.execute('INSERT INTO review_tickets VALUES(?,?,?,?,?,?)',(tid,uid,grant['guardian'],now,now+180,'pending'))
        return {'id':tid,'expires':now+180,'notice':NOTICE}
    if len(parts)==3 and parts[:2]==['enrollment','tickets']:
        row=r.one('SELECT * FROM review_tickets WHERE id=? AND child=?',(parts[2],uid))
        if not row:raise ApiError(404,'Captura indisponível.')
        if method=='DELETE':r.execute('DELETE FROM review_tickets WHERE id=?',(row['id'],));return {'ok':True}
        if method=='POST':
            prerequisites(s,u)
            if row['state']!='pending' or row['expires']<=now:raise ApiError(409,'Captura utilizada ou expirada.')
            encoded=text(data,'image',100,900000)
            try:content=base64.b64decode(encoded,validate=True)
            except ValueError:raise ApiError(400,'Captura inválida.')
            if len(content)>650000:raise ApiError(413,'Captura muito grande.')
            r.execute("UPDATE review_tickets SET state='processing' WHERE id=?",(row['id'],))
            return SubmitCapture(s,uid,row,content)
    if path=='/admin/enrollments' and method=='GET':
        reviewer(s,u)
        rows=r.rows('''SELECT c.id,c.child,c.state,c.created,c.updated,c.reason,u.name childName,g.name guardianName,
            EXISTS(SELECT 1 FROM review_photos p WHERE p.review=c.id AND p.expires>?) hasPhoto
            FROM enrollment_reviews c JOIN users u ON u.id=c.child JOIN users g ON g.id=c.guardian
            JOIN guardian_links l ON l.child=c.child AND l.guardian=c.guardian
            JOIN review_consents a ON a.child=c.child AND a.guardian=c.guardian AND a.granted=1 AND a.version=?
            WHERE c.guardian!=? AND c.id=(SELECT x.id FROM enrollment_reviews x WHERE x.child=c.child ORDER BY x.created DESC,x.id DESC LIMIT 1)
            ORDER BY CASE WHEN c.state IN ('pending','additional_review') THEN 0 ELSE 1 END,c.created LIMIT 100''',(now,VERSION,uid))
        return {'items':rows}
    if len(parts)>=3 and parts[:2]==['admin','enrollments']:
        reviewer(s,u)
        case=r.one('SELECT * FROM enrollment_reviews WHERE id=?',(parts[2],))
        if not case:raise ApiError(404,'Revisão indisponível.')
        reviewer(s,u,case)
        child=r.one('SELECT * FROM users WHERE id=?',(case['child'],))
        active=current(s,case['child'])
        if not child or not consent(s,case['child']) or not active or active['id']!=case['id'] or active['guardian']!=case['guardian']:
            raise ApiError(404,'Revisão revogada ou substituída.')
        if len(parts)==3 and method=='GET':
            return {'case':dict(case,declaredAge=age(child['birth']),childName=child['name']),
                    'checks':{'childEmail':bool(child['verified']),'family':bool(s.family_approved(child))},
                    'history':r.rows("SELECT e.action,e.reason,e.created,coalesce(u.name,'Sistema') actorName FROM review_events e LEFT JOIN users u ON u.id=e.actor WHERE review=? ORDER BY created",(case['id'],)),
                    'hasPhoto':bool(r.one('SELECT 1 FROM review_photos WHERE review=? AND expires>?',(case['id'],now))),'notice':NOTICE}
        if len(parts)==4 and parts[3]=='photo' and method=='GET':
            row=r.one('SELECT * FROM review_photos WHERE review=? AND expires>?',(case['id'],now))
            if not row or case['state'] not in ('pending','additional_review'):raise ApiError(404,'Captura indisponível ou já descartada.')
            if not s.review_vault:raise ApiError(503,'Chave de revisão indisponível.')
            return ReviewPhoto(s,case['id'],row['cipher'])
        if len(parts)==4 and parts[3]=='decision' and method=='POST':
            if case['state'] not in ('pending','additional_review'):raise ApiError(409,'Esta revisão já foi encerrada.')
            action=data.get('action');reason=text(data,'reason',10,500)
            if action not in ('approved','correction','additional_review'):raise ApiError(400,'Decisão inválida.')
            if action=='approved':
                prerequisites(s,child)
                if data.get('captureUsable') is not True or data.get('dataReviewed') is not True:raise ApiError(400,'Confirme a legibilidade da captura e a revisão dos dados.')
                if not r.one('SELECT 1 FROM review_photos WHERE review=? AND expires>?',(case['id'],now)):raise ApiError(409,'A captura expirou. Solicite nova captura.')
                if not r.one("SELECT 1 FROM review_events WHERE review=? AND actor=? AND action='capture.read'",(case['id'],uid)):raise ApiError(400,'Consulte a captura antes de concluir a revisão.')
            r.execute('UPDATE enrollment_reviews SET state=?,reason=?,reviewer=?,updated=? WHERE id=?',(action,reason,uid,now,case['id']))
            event(s,case['id'],uid,'decision.'+action,reason)
            if action!='additional_review':r.execute('DELETE FROM review_photos WHERE review=?',(case['id'],))
            s.notification(case['child'],'Seu cadastro recebeu uma atualização. Consulte a revisão do cadastro.')
            s.notification(case['guardian'],'O cadastro de um perfil da sua família recebeu uma atualização. Consulte Minha família.')
            return {'state':action}
    raise ApiError(404,'Recurso de revisão indisponível.')

class SubmitCapture:
    def __init__(self,s,uid,ticket,content):self.s,self.uid,self.ticket,self.content=s,uid,ticket,content
    def resolve(self,bearer):
        from images import normalize
        from PIL import Image
        from io import BytesIO
        try:
            if not self.s.review_vault:raise ApiError(503,'Chave de revisão indisponível.')
            with Image.open(BytesIO(self.content)) as image:
                if image.format!='JPEG' or min(image.size)<240 or max(image.size)>1280:raise ApiError(400,'Use uma captura JPEG de 240 a 1280 pixels por lado.')
            _,clean=normalize({'mime':'image/jpeg','data':base64.b64encode(self.content).decode()})
            cipher=self.s.review_vault.encrypt(clean)
        except ApiError:raise
        except (OSError,ValueError):raise ApiError(400,'Não foi possível validar a captura JPEG.')
        finally:self.content=b''
        with self.s.lock,self.s.repo.transaction():
            self.s._guardian_checks={};u=self.s.user(bearer)
            if u['id']!=self.uid:raise ApiError(404,'Captura indisponível.')
            prerequisites(self.s,u);r=self.s.repo;grant=consent(self.s,u['id']);now=time.time()
            ticket=r.one("SELECT * FROM review_tickets WHERE id=? AND state='processing' AND expires>?",(self.ticket['id'],now))
            if not ticket or grant['guardian']!=self.ticket['guardian']:raise ApiError(409,'Envio cancelado ou expirado.')
            old=current(self.s,self.uid)
            if old:
                if old['state']=='approved':raise ApiError(409,'Cadastro já aprovado.')
                r.execute("UPDATE enrollment_reviews SET state='superseded',updated=? WHERE id=?",(now,old['id']))
                r.execute('DELETE FROM review_photos WHERE review=?',(old['id'],))
            rid=token()
            r.execute('INSERT INTO enrollment_reviews VALUES(?,?,?,?,?,?,?,?,NULL)',(rid,self.uid,grant['guardian'],VERSION,'pending','',now,now))
            r.execute('INSERT INTO review_photos VALUES(?,?,?)',(rid,cipher,now+48*3600))
            r.execute('DELETE FROM review_tickets WHERE id=?',(ticket['id'],))
            event(self.s,rid,self.uid,'capture.submitted')
            return status(self.s,self.uid)

class ReviewPhoto:
    def __init__(self,s,rid,cipher):self.s,self.rid,self.cipher=s,rid,cipher
    def resolve(self,bearer):
        try:raw=self.s.review_vault.decrypt(self.cipher)
        except Exception:raise ApiError(503,'Não foi possível abrir a captura protegida.')
        with self.s.lock,self.s.repo.transaction():
            self.s._guardian_checks={};u=self.s.user(bearer)
            row=self.s.repo.one('SELECT * FROM enrollment_reviews WHERE id=?',(self.rid,))
            if not row:raise ApiError(404,'Revisão indisponível.')
            reviewer(self.s,u,row);active=current(self.s,row['child'])
            if not consent(self.s,row['child']) or not active or active['id']!=row['id'] or row['state'] not in ('pending','additional_review') or not self.s.repo.one('SELECT 1 FROM review_photos WHERE review=? AND cipher=? AND expires>?',(self.rid,self.cipher,time.time())):
                raise ApiError(404,'Captura revogada, expirada ou descartada.')
            event(self.s,row['id'],u['id'],'capture.read')
        return {'mime':'image/jpeg','data':base64.b64encode(raw).decode()}
