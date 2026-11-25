"""Safety reports: authorize evidence, triage, and preserve reporter privacy.

Priorities route human review; they never infer guilt or automatically remove content.
"""
import time
from security import ApiError, age, text, token

CATEGORIES = {
    'bullying': 2, 'unwanted_contact': 2, 'personal_information': 2,
    'inappropriate_content': 1, 'hate': 2, 'threat': 3,
    'child_safety': 3, 'scam': 2, 'other': 1,
}


def submit_report(service, actor, data):
    repo = service.repo
    category = data.get('category', 'other')
    if not isinstance(category, str) or category not in CATEGORIES:
        raise ApiError(400, 'Categoria de denúncia inválida.')
    share = data.get('notifyGuardian', False)
    if not isinstance(share, bool):
        raise ApiError(400, 'Preferência de apoio inválida.')
    reason = text(data, 'reason', 3, 1000)
    target = text(data, 'target', 1, 200)
    kind, evidence = 'general', None
    if target != 'general':
        # Resolve only content already accessible to this reporter. Messages
        # are an exception after blocking: participants may still report them.
        message = repo.one('SELECT * FROM messages WHERE id=? AND (sender=? OR recipient=?)', (target, actor['id'], actor['id']))
        post = repo.one('SELECT * FROM posts WHERE id=?', (target,))
        comment = repo.one('SELECT * FROM comments WHERE id=?', (target,))
        person = repo.one('SELECT * FROM users WHERE id=?', (target,))
        if message:
            kind, evidence = 'message', message['text']
        elif post:
            service.active(actor)
            service.post(actor, target)
            kind, evidence = 'post', post['text']
        elif comment:
            service.active(actor)
            service.post(actor, comment['post'])
            kind, evidence = 'comment', comment['text']
        elif person:
            # Reporting a known profile must remain possible after blocking.
            known = service.visible(actor, person) or repo.one('SELECT 1 FROM blocks WHERE user=? AND target=?', (actor['id'], target))
            known = known or repo.one('SELECT 1 FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?) LIMIT 1', (actor['id'], target, target, actor['id']))
            if not known:
                raise ApiError(404, 'Alvo indisponível para denúncia.')
            kind = 'profile'
        else:
            raise ApiError(404, 'Alvo indisponível para denúncia.')
    # Do not flood the queue when a client retries the same report.
    previous = repo.one("""SELECT r.id,r.status FROM reports r JOIN report_context c ON c.report=r.id
        WHERE r.user=? AND r.target=? AND r.status='pending' AND c.category=? ORDER BY r.created DESC LIMIT 1""",
        (actor['id'], target, category))
    if previous:
        return dict(previous, message='Este relato já está na fila de análise.')
    service.limit(('reports', actor['id']), 10, 3600)
    rid = token()
    repo.execute('INSERT INTO reports(id,user,target,reason,created) VALUES(?,?,?,?,?)', (rid, actor['id'], target, reason, time.time()))
    repo.execute('INSERT INTO report_context VALUES(?,?,?,?,?)', (rid, category, CATEGORIES[category], kind, evidence))
    if share and age(actor['birth']) < 18:
        link = service.guardian_link(actor)
        if link and link['state'] == 'active' and not service.suspended(link['guardian']):
            service.notification(link['guardian'], 'Um perfil da sua família pediu seu apoio em uma situação de segurança. Converse com ele com acolhimento.')
    # Never notify the reported account or disclose the reporter to it.
    service.audit('report.created', actor['id'])
    return {'id': rid, 'status': 'pending', 'message': 'Relato registrado para análise humana. Em risco imediato, procure um adulto de confiança. Atendimento contínuo ainda precisa ser configurado.'}
