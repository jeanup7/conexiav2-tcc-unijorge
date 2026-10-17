"""Recipient acceptance plus consent from each minor's current guardian."""
import time
from security import ApiError, age, text, token


class Contacts:
    def __init__(self, service):
        self.s, self.r = service, service.repo

    def required(self, source, target):
        consents = {}
        for person in (source, target):
            self.s.active(person)
            if age(person['birth']) < 18:
                link = self.s.guardian_link(person)
                if not link or link['state'] != 'active':
                    raise ApiError(403, 'O vínculo familiar precisa estar ativo.')
                consents[person['id']] = link['guardian']
        return consents

    def pending(self, rid):
        request = self.r.one("SELECT * FROM contact_requests WHERE id=? AND status='pending' AND expires>?", (rid, time.time()))
        if not request:
            raise ApiError(404, 'Pedido indisponível ou expirado.')
        if self.s.blocked(request['source'], request['target']):
            raise ApiError(404, 'Pedido indisponível.')
        return request

    def sync(self, request):
        people = [self.r.one('SELECT * FROM users WHERE id=?', (request[key],)) for key in ('source', 'target')]
        required = self.required(*people)
        saved = {v['child']: v for v in self.r.rows('SELECT * FROM contact_consents WHERE request=?', (request['id'],))}
        for child, guardian in required.items():
            old = saved.get(child)
            if not old or old['guardian'] != guardian:
                self.r.execute('INSERT OR REPLACE INTO contact_consents VALUES(?,?,?,0)', (request['id'], child, guardian))
        for child in saved.keys() - required.keys():
            self.r.execute('DELETE FROM contact_consents WHERE request=? AND child=?', (request['id'], child))
        return required

    def finish(self, request):
        self.sync(request)
        waiting = self.r.one('SELECT 1 FROM contact_consents WHERE request=? AND approved=0', (request['id'],))
        if not request['accepted'] or waiting:
            return {'ok': True, 'status': 'awaiting_guardian' if request['accepted'] else 'pending'}
        for source, target in ((request['source'], request['target']), (request['target'], request['source'])):
            self.r.execute('INSERT OR REPLACE INTO contacts VALUES(?,?,1)', (source, target))
            self.s.notification(source, 'Uma conexão foi aprovada com as autorizações necessárias.')
        self.r.execute("UPDATE contact_requests SET status='approved' WHERE id=?", (request['id'],))
        self.s.audit('contact.approved', request['target'])
        return {'ok': True, 'status': 'approved'}

    def create(self, actor, target):
        other = self.r.one('SELECT * FROM users WHERE id=?', (target,))
        if not other or actor['id'] == target or self.s.blocked(actor['id'], target):
            raise ApiError(404, 'Perfil indisponível.')
        required = self.required(actor, other)
        if self.s.contact(actor['id'], target):
            return {'status': 'approved'}
        self.r.execute("UPDATE contact_requests SET status='expired' WHERE status='pending' AND expires<=?", (time.time(),))
        previous = self.r.one("SELECT * FROM contact_requests WHERE status='pending' AND ((source=? AND target=?) OR (source=? AND target=?))", (actor['id'], target, target, actor['id']))
        if previous:
            return {'status': 'pending', 'requestId': previous['id']}
        self.s.limit(('contacts', actor['id']), 20, 3600)
        rid = token()
        self.r.execute('INSERT INTO contact_requests VALUES(?,?,?,0,?,?,?)', (rid, actor['id'], target, 'pending', time.time(), time.time() + 7 * 86400))
        self.r.execute('INSERT OR REPLACE INTO contacts VALUES(?,?,0)', (actor['id'], target))
        for child, guardian in required.items():
            self.r.execute('INSERT INTO contact_consents VALUES(?,?,?,0)', (rid, child, guardian))
            self.s.notification(guardian, 'Um perfil vinculado tem um pedido de contato para analisar.')
        self.s.notification(target, 'Você recebeu um pedido de contato.')
        return {'status': 'pending', 'requestId': rid}

    def accept(self, actor, source):
        request = self.r.one("SELECT * FROM contact_requests WHERE source=? AND target=? AND status='pending' AND expires>?", (source, actor['id'], time.time()))
        if not request:
            if self.s.contact(actor['id'], source) and not self.s.blocked(actor['id'], source):
                other = self.r.one('SELECT * FROM users WHERE id=?', (source,))
                self.s.active(other)
                return {'ok': True, 'status': 'approved'}
            raise ApiError(404, 'Pedido indisponível ou expirado.')
        request = self.pending(request['id'])
        self.sync(request)
        self.r.execute('UPDATE contact_requests SET accepted=1 WHERE id=?', (request['id'],))
        request['accepted'] = 1
        return self.finish(request)

    def requests(self, actor):
        rows = self.r.rows("SELECT q.*,u.id counterpart,u.name,u.birth FROM contact_requests q JOIN users u ON u.id=CASE WHEN q.source=? THEN q.target ELSE q.source END WHERE (q.target=? OR q.source=?) AND q.status='pending' AND q.expires>? ORDER BY q.created DESC LIMIT 100", (actor['id'], actor['id'], actor['id'], time.time()))
        return {'items': [{'id': v['counterpart'], 'requestId': v['id'], 'name': v['name'], 'incoming': v['target'] == actor['id'], 'accepted': bool(v['accepted']), 'requiresGuardian': age(actor['birth']) < 18 or age(v['birth']) < 18} for v in rows if not self.s.blocked(actor['id'], v['counterpart'])]}

    def child(self, actor, cid):
        self.s.active(actor)
        link = self.r.one('SELECT * FROM guardian_links WHERE child=? AND guardian=?', (cid, actor['id']))
        if age(actor['birth']) < 18 or not link:
            raise ApiError(404, 'Vínculo indisponível.')
        return link

    def family_list(self, actor, cid):
        self.child(actor, cid)
        rows = self.r.rows("SELECT q.*,u.name FROM contact_requests q JOIN users u ON u.id=CASE WHEN q.source=? THEN q.target ELSE q.source END WHERE (q.source=? OR q.target=?) AND (q.status='approved' OR (q.status='pending' AND q.expires>?)) ORDER BY q.created DESC LIMIT 100", (cid, cid, cid, time.time()))
        result = []
        for request in rows:
            if self.s.blocked(request['source'], request['target']):
                continue
            consent = self.r.one('SELECT * FROM contact_consents WHERE request=? AND child=? AND guardian=?', (request['id'], cid, actor['id']))
            other = request['target'] if request['source'] == cid else request['source']
            status = 'approved' if request['status'] == 'approved' and self.s.contact(cid, other) else 'pending'
            result.append({'id': request['id'], 'name': request['name'], 'incoming': request['target'] == cid, 'accepted': bool(request['accepted']), 'approved': bool(consent and consent['approved']), 'status': status})
        return {'items': result}

    def decide(self, actor, cid, rid, data):
        link = self.child(actor, cid)
        request = self.r.one("SELECT * FROM contact_requests WHERE id=? AND (status='approved' OR (status='pending' AND expires>?))", (rid, time.time()))
        if not request:
            raise ApiError(404, 'Pedido indisponível.')
        if cid not in (request['source'], request['target']):
            raise ApiError(404, 'Pedido indisponível.')
        approved = data.get('approved')
        if not isinstance(approved, bool):
            raise ApiError(400, 'Decisão inválida.')
        if not approved:
            if request['status'] == 'approved':
                self.disconnect(request['source'], request['target'])
                self.s.audit('contact.guardian.revoked', actor['id'])
                return {'ok': True, 'status': 'cancelled'}
            return self.reject(request, actor['id'])
        if request['status'] == 'approved':
            if self.s.contact(request['source'],request['target']):
                return {'ok': True, 'status': 'approved'}
            # A guardian change invalidates inherited consent without discarding acceptance.
            self.r.execute("UPDATE contact_requests SET status='pending',expires=? WHERE id=?", (time.time()+7*86400,rid))
            self.r.execute('UPDATE contacts SET approved=0 WHERE (user=? AND target=?) OR (user=? AND target=?)', (request['source'],request['target'],request['target'],request['source']))
            request['status'] = 'pending'
        self.pending(rid)
        if link['state'] != 'active':
            raise ApiError(403, 'Reative o vínculo antes de autorizar contatos.')
        self.sync(request)
        self.r.execute('UPDATE contact_consents SET approved=1 WHERE request=? AND child=? AND guardian=?', (rid, cid, actor['id']))
        self.s.audit('contact.guardian.consent', actor['id'])
        return self.finish(request)

    def reject(self, request, actor):
        self.r.execute("UPDATE contact_requests SET status='rejected' WHERE id=?", (request['id'],))
        self.r.execute('DELETE FROM contacts WHERE approved=0 AND ((user=? AND target=?) OR (user=? AND target=?))', (request['source'], request['target'], request['target'], request['source']))
        self.s.audit('contact.rejected', actor)
        return {'ok': True, 'status': 'rejected'}

    def cancel(self, actor, rid):
        request = self.pending(rid)
        if actor['id'] not in (request['source'], request['target']):
            raise ApiError(404, 'Pedido indisponível.')
        return self.reject(request, actor['id'])

    def disconnect(self, actor, target):
        self.r.execute('DELETE FROM contacts WHERE (user=? AND target=?) OR (user=? AND target=?)', (actor, target, target, actor))
        self.r.execute("UPDATE contact_requests SET status='cancelled' WHERE status IN ('pending','approved') AND ((source=? AND target=?) OR (source=? AND target=?))", (actor, target, target, actor))
