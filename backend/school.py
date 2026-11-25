"""Explicit guardian delegation, recipient acceptance and revocable school access.
No general tutor role or inherited access to private messages/media.
"""
import time
from security import ApiError, age, text, token

CONSENT_VERSION='school-v1'

def dispatch_school(s,actor,method,path,data):
    r=s.repo; uid=actor['id']; parts=path.strip('/').split('/'); now=time.time()
    s.active(actor)
    def audit(cid,event):
        r.execute('INSERT INTO school_audit VALUES(?,?,?,?,?)',(token(),cid,uid,event,now))
        s.audit('school.'+event,uid)
    def family(cid):
        child=r.one('SELECT * FROM users WHERE id=?',(cid,))
        link=r.one('SELECT * FROM guardian_links WHERE child=?',(cid,))
        if not child or not link or age(child['birth'])>=18: raise ApiError(404,'Aluno indisponível.')
        return child,link
    def parent(cid):
        child,link=family(cid)
        if link['guardian']!=uid or age(actor['birth'])<18:raise ApiError(404,'Aluno indisponível.')
        return child,link
    def mode(cid):
        pref=r.one('SELECT mode FROM school_privacy WHERE child=?',(cid,))
        return pref['mode'] if pref else 'guardian_only'
    def allowed(link):
        child,fam=family(link['child'])
        if link['state']!='active' or fam['guardian']!=link['guardian'] or fam['state']!='active' or mode(child['id'])!='shared':raise ApiError(403,'Acompanhamento escolar não autorizado.')
        guardian=r.one('SELECT * FROM users WHERE id=?',(fam['guardian'],))
        s.active(child);s.active(guardian)
        if s.blocked(uid,child['id']) or s.blocked(uid,guardian['id']):raise ApiError(403,'Acompanhamento indisponível.')
        return child
    r.execute("UPDATE tutor_links SET state='expired',updated=? WHERE state='pending' AND expires<=?",(now,now))
    if path=='/school/tutor-candidates' and method=='GET':
        if age(actor['birth'])<18:raise ApiError(403,'Somente responsáveis podem convidar tutores.')
        # The selector exposes approved adult contacts, never an email directory.
        items=[]
        for candidate in r.rows('SELECT u.* FROM users u JOIN contacts c ON c.target=u.id WHERE c.user=? AND c.approved=1 ORDER BY u.name,u.id LIMIT 100',(uid,)):
            if age(candidate['birth'])<18 or not s.contact(uid,candidate['id']) or s.blocked(uid,candidate['id']):continue
            try:s.active(candidate)
            except ApiError:continue
            items.append({'id':candidate['id'],'name':candidate['name']})
        return {'items':items}
    if path=='/school/invitations' and method=='GET':
        # Minimal information before acceptance: only inviter and selected scope.
        return {'items':r.rows("SELECT t.id,t.scope,t.state,t.created,t.expires,u.name guardian FROM tutor_links t JOIN users u ON u.id=t.guardian WHERE t.tutor=? AND t.state='pending' ORDER BY t.created DESC LIMIT 100",(uid,)),'consentVersion':CONSENT_VERSION}
    if path=='/school/students' and method=='GET':
        items=[]
        for link in r.rows("SELECT * FROM tutor_links WHERE tutor=? AND state='active' ORDER BY created DESC LIMIT 100",(uid,)):
            try:child=allowed(link)
            except ApiError:continue
            items.append({'id':child['id'],'name':child['name'],'scope':link['scope']})
        return {'items':items}
    if len(parts)==4 and parts[:2]==['school','invitations'] and parts[3]=='decision' and method=='POST':
        link=r.one('SELECT * FROM tutor_links WHERE id=? AND tutor=?',(parts[2],uid))
        if not link:raise ApiError(404,'Convite indisponível.')
        accept=data.get('accept')
        if not isinstance(accept,bool):raise ApiError(400,'Informe accept como booleano.')
        desired='active' if accept else 'declined'
        if link['state']==desired:return {'state':desired}
        if link['state']!='pending':raise ApiError(409,'Convite encerrado ou expirado.')
        child,fam=family(link['child'])
        if fam['guardian']!=link['guardian'] or fam['state']!='active':raise ApiError(403,'Vínculo familiar indisponível.')
        if age(actor['birth'])<18:raise ApiError(403,'O tutor precisa ser adulto.')
        if s.blocked(uid,child['id']) or s.blocked(uid,fam['guardian']):raise ApiError(403,'Contato bloqueado.')
        r.execute('UPDATE tutor_links SET state=?,updated=? WHERE id=?',(desired,now,link['id']))
        audit(child['id'],'invitation.'+desired)
        return {'state':desired}
    if len(parts)>=4 and parts[:2]==['school','children']:
        cid=parts[2];resource=parts[3]
        if len(parts)==4 and resource=='activity' and method=='GET':
            link=r.one("SELECT * FROM tutor_links WHERE child=? AND tutor=? AND state='active'",(cid,uid))
            if not link:raise ApiError(404,'Aluno indisponível.')
            child=allowed(link)
            try:days=int(data.get('days',7))
            except (ValueError,TypeError):raise ApiError(400,'Use 7 ou 30 dias.')
            if days not in (7,30):raise ApiError(400,'Use 7 ou 30 dias.')
            # Share only events after delegation, never the child's prior history.
            preference=r.one('SELECT updated FROM school_privacy WHERE child=?',(cid,))
            since=max(now-days*86400,link['updated'],preference['updated'])
            rows=r.rows('SELECT category,COUNT(*) count FROM feed_views WHERE child=? AND first_seen>=? GROUP BY category ORDER BY count DESC',(cid,since))
            result={'child':{'id':cid,'name':child['name']},'days':days,'scope':link['scope'],'categories':rows,'total':sum(v['count'] for v in rows),'notice':'Atividade no feed após o aceite. Ver não significa gostar. Sem mensagens privadas ou imagens.'}
            if link['scope']=='history':
                result['history']=r.rows('SELECT category,first_seen seenAt FROM feed_views WHERE child=? AND first_seen>=? ORDER BY first_seen DESC LIMIT 50',(cid,since))
            audit(cid,'activity.read')
            return result
        child,fam=family(cid)
        if len(parts)==4 and resource in ('privacy','tutors','audit') and method=='GET':
            if uid not in (cid,fam['guardian']):raise ApiError(404,'Aluno indisponível.')
            if resource=='privacy':return {'mode':mode(cid),'consentVersion':CONSENT_VERSION}
            if resource=='audit':return {'items':r.rows('SELECT event,created FROM school_audit WHERE child=? ORDER BY created DESC LIMIT 100',(cid,))}
            return {'items':r.rows('SELECT t.id,t.scope,t.state,t.created,t.expires,u.name FROM tutor_links t JOIN users u ON u.id=t.tutor WHERE t.child=? AND t.guardian=? ORDER BY t.created DESC LIMIT 100',(cid,fam['guardian']))}
        parent(cid)
        if len(parts)==4 and resource=='privacy' and method=='PATCH':
            value=data.get('mode')
            if value not in ('guardian_only','shared','paused'):raise ApiError(400,'Modo inválido.')
            # Repeated saves must not reset the start of the shared history.
            if mode(cid)==value:return {'mode':value}
            r.execute('INSERT INTO school_privacy VALUES(?,?,?) ON CONFLICT(child) DO UPDATE SET mode=excluded.mode,updated=excluded.updated',(cid,value,now))
            audit(cid,'privacy.'+value);return {'mode':value}
        if len(parts)==4 and resource=='tutors' and method=='POST':
            if data.get('consent') is not True or data.get('consentVersion')!=CONSENT_VERSION:raise ApiError(400,'Confirme o consentimento school-v1.')
            if fam['state']!='active':raise ApiError(403,'Vínculo familiar pausado.')
            s.active(child)
            tid=text(data,'tutorId',1,200);scope=data.get('scope','summary')
            if scope not in ('summary','history'):raise ApiError(400,'Escopo inválido.')
            tutor=r.one('SELECT * FROM users WHERE id=?',(tid,))
            if not tutor or age(tutor['birth'])<18 or tid in (uid,cid):raise ApiError(400,'Escolha outra conta adulta verificada.')
            s.active(tutor)
            if s.blocked(tid,uid) or s.blocked(tid,cid):raise ApiError(403,'Contato bloqueado.')
            existing=r.one("SELECT * FROM tutor_links WHERE child=? AND tutor=? AND state IN ('pending','active')",(cid,tid))
            if existing:
                if existing['guardian']!=uid or existing['scope']!=scope:raise ApiError(409,'Revogue o vínculo anterior antes de alterar permissões.')
                return {'id':existing['id'],'state':existing['state']}
            s.limit(('school.invites',uid),20,3600)
            rid=token()
            r.execute('INSERT INTO tutor_links VALUES(?,?,?,?,?,?,?,?,?,?)',(rid,cid,uid,tid,scope,'pending',CONSENT_VERSION,now,now+7*86400,now))
            audit(cid,'invitation.created');s.notification(tid,'Você recebeu um convite de acompanhamento escolar.')
            return {'id':rid,'state':'pending','expires':now+7*86400}
        if len(parts)==5 and resource=='tutors' and method=='DELETE':
            link=r.one('SELECT * FROM tutor_links WHERE id=? AND child=? AND guardian=?',(parts[4],cid,uid))
            if not link:raise ApiError(404,'Vínculo indisponível.')
            if link['state']!='revoked':
                r.execute("UPDATE tutor_links SET state='revoked',updated=? WHERE id=?",(now,link['id']));audit(cid,'invitation.revoked')
            return {'state':'revoked'}
    raise ApiError(404,'Recurso escolar não encontrado.')
