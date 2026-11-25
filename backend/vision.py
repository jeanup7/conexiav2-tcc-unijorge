"""Opt-in age/PAD research. Captures never enter SQLite, media or cloud storage."""
import base64
import hashlib
import json
import random
import time
from threading import Lock
from security import ApiError, age, token

VERSION='vision-research-v1'
CAPTURE_LOCK=Lock()
NOTICE='Experimento acadêmico: não comprova idade, identidade, parentesco ou presença real. Não libera nem bloqueia o feed. Capturas processadas em memória; resultado disponível por 24 horas, com limpeza periódica dos metadados.'

def eligible(s,u):
    if s.suspended(u['id']) or not u['verified'] or not s.approved(u):
        raise ApiError(403,'Confirme os e-mails e mantenha o vínculo familiar ativo antes do experimento.')
    if age(u['birth'])<18:
        link=s.guardian_link(u)
        consent=s.repo.one('SELECT * FROM vision_consents WHERE child=?',(u['id'],))
        if not consent or not consent['granted'] or consent['version']!=VERSION or not link or consent['guardian']!=link['guardian']:
            raise ApiError(403,'Seu responsável precisa autorizar este experimento no painel da família.')

def dispatch_vision(s,u,method,path,data):
    if not s.development:raise ApiError(404,'Recurso experimental indisponível.')
    r=s.repo;uid=u['id'];parts=path.strip('/').split('/');now=time.time()
    if path=='/vision/status' and method=='GET':
        return {'enabled':s.vision_models is not None,'experimental':True,'grantsAccess':False,'consentVersion':VERSION,'notice':NOTICE}
    if len(parts)==4 and parts[:2]==['vision','children'] and parts[3]=='consent' and method in ('GET','POST'):
        s.active(u)
        link=r.one('SELECT * FROM guardian_links WHERE child=? AND guardian=?',(parts[2],uid))
        if not link or age(u['birth'])<18:raise ApiError(404,'Perfil indisponível.')
        if method=='GET':
            saved=r.one('SELECT granted FROM vision_consents WHERE child=? AND guardian=?',(parts[2],uid))
            return {'granted':bool(saved and saved['granted']),'consentVersion':VERSION,'notice':NOTICE}
        granted=data.get('granted')
        if not isinstance(granted,bool) or data.get('consentVersion')!=VERSION:raise ApiError(400,'Revise a autorização do experimento.')
        r.execute('INSERT INTO vision_consents VALUES(?,?,?,?,?) ON CONFLICT(child) DO UPDATE SET guardian=excluded.guardian,granted=excluded.granted,version=excluded.version,updated=excluded.updated',(parts[2],uid,int(granted),VERSION,now))
        if not granted:r.execute('DELETE FROM vision_sessions WHERE user=?',(parts[2],))
        return {'granted':granted,'notice':NOTICE}
    eligible(s,u)
    if path=='/vision/sessions' and method=='POST':
        if s.vision_models is None:raise ApiError(503,'Modelos experimentais ainda não configurados no servidor.')
        if data.get('consent') is not True or data.get('consentVersion')!=VERSION:raise ApiError(400,'Leia e aceite a participação experimental.')
        limit=r.one('SELECT * FROM vision_limits WHERE user=?',(uid,))
        if limit and limit['reset']>now and limit['count']>=6:raise ApiError(429,'Limite de seis sessões por hora. Tente mais tarde.')
        if not limit or limit['reset']<=now:
            r.execute('INSERT INTO vision_limits VALUES(?,?,1) ON CONFLICT(user) DO UPDATE SET reset=excluded.reset,count=1',(uid,now+3600))
        else:r.execute('UPDATE vision_limits SET count=count+1 WHERE user=?',(uid,))
        r.execute("UPDATE vision_sessions SET state='cancelled' WHERE user=? AND state='pending'",(uid,))
        sides=random.SystemRandom().sample(['left','right'],2)
        challenge=['front',*sides];sid=token()
        r.execute('INSERT INTO vision_sessions VALUES(?,?,?,?,?,?,?,NULL)',(sid,uid,VERSION,json.dumps(challenge),'pending',now,now+180))
        return {'id':sid,'challenge':challenge,'expires':now+180,'notice':NOTICE}
    if len(parts)==3 and parts[:2]==['vision','sessions']:
        row=r.one('SELECT * FROM vision_sessions WHERE id=? AND user=? AND created>?',(parts[2],uid,now-86400))
        if not row:raise ApiError(404,'Sessão experimental indisponível.')
        if method=='GET':return {'id':row['id'],'state':row['state'],'result':json.loads(row['result']) if row['result'] else None,'notice':NOTICE}
        if method=='DELETE':
            r.execute('DELETE FROM vision_sessions WHERE id=? AND user=?',(row['id'],uid))
            return {'ok':True}
    if len(parts)==4 and parts[:2]==['vision','sessions'] and parts[3]=='capture' and method=='POST':
        row=r.one('SELECT * FROM vision_sessions WHERE id=? AND user=?',(parts[2],uid))
        if not row or row['version']!=VERSION or row['state']!='pending' or row['expires']<=now:raise ApiError(409,'Sessão encerrada ou expirada. Inicie outra captura.')
        if now-row['created']<2:raise ApiError(400,'Realize a captura guiada antes de enviar.')
        if s.vision_models is None:raise ApiError(503,'Modelos indisponíveis.')
        frames=data.get('frames')
        if not isinstance(frames,list) or len(frames)!=3:raise ApiError(400,'Envie as três capturas guiadas.')
        decoded=[]
        for frame in frames:
            if not isinstance(frame,str) or len(frame)>900000:raise ApiError(413,'Captura excede o limite permitido.')
            try:content=base64.b64decode(frame,validate=True)
            except (ValueError,TypeError):raise ApiError(400,'Captura inválida.')
            if not 100<=len(content)<=650000:raise ApiError(400,'Tamanho de captura inválido.')
            decoded.append(content)
        if len({hashlib.sha256(v).digest() for v in decoded})!=3:raise ApiError(400,'Não repita a mesma imagem nas três etapas.')
        r.execute("UPDATE vision_sessions SET state='processing' WHERE id=?",(row['id'],))
        return CaptureJob(s,u['id'],row['id'],decoded,json.loads(row['challenge']))
    raise ApiError(404,'Recurso experimental indisponível.')

class CaptureJob:
    def __init__(self,s,uid,sid,contents,challenge):
        self.s,self.uid,self.sid,self.contents,self.challenge=s,uid,sid,contents,challenge
    def resolve(self,bearer):
        acquired=CAPTURE_LOCK.acquire(blocking=False)
        try:
            if not acquired:raise RuntimeError('busy')
            # Decode/normalize with existing anti-bomb/metadata stripping rules.
            from images import normalize
            from PIL import Image
            from io import BytesIO
            clean=[]
            for content in self.contents:
                with Image.open(BytesIO(content)) as image:
                    if image.format!='JPEG':raise ValueError('jpeg_required')
                    if min(image.size)<240 or max(image.size)>1280:raise ValueError('resolution')
                _,value=normalize({'mime':'image/jpeg','data':base64.b64encode(content).decode()})
                clean.append(value)
            result=self.s.vision_models.analyze(clean,self.challenge)
            # Never accept a provider's approval flag, even accidentally.
            result=dict(result,experimental=True,grantsAccess=False)
        except Exception:
            result={'experimental':True,'grantsAccess':False,'result':'inconclusive','reason':'capture_or_model_failure'}
        finally:
            self.contents.clear()
            if acquired:CAPTURE_LOCK.release()
        with self.s.lock,self.s.repo.transaction():
            self.s._guardian_checks={}
            actor=self.s.user(bearer)
            if actor['id']!=self.uid:raise ApiError(404,'Sessão indisponível.')
            eligible(self.s,actor)
            row=self.s.repo.one("SELECT id FROM vision_sessions WHERE id=? AND user=? AND state='processing' AND expires>?",(self.sid,self.uid,time.time()))
            if not row:raise ApiError(409,'Sessão encerrada durante o processamento.')
            self.s.repo.execute("UPDATE vision_sessions SET state='complete',result=? WHERE id=?",(json.dumps(result,allow_nan=False),self.sid))
        return {'result':result,'notice':NOTICE}
