"""Local development moderation. Roles are granted on the backend host only."""
import time
from security import ApiError, age, digest, token, text


def dispatch_admin(service, actor, method, path, data):
    repo = service.repo
    if not service.development or not repo.one('SELECT 1 FROM administrators WHERE user=?', (actor['id'],)):
        raise ApiError(403, 'Acesso restrito à administração local.')
    service.active(actor)
    if age(actor['birth']) < 18:
        raise ApiError(403, 'A administração exige uma conta adulta.')
    if path == '/admin/summary' and method == 'GET':
        summary={key: repo.one(sql)['n'] for key, sql in {
            'users': 'SELECT count(*) n FROM users',
            'posts': 'SELECT count(*) n FROM posts WHERE story=0',
            'pendingReports': "SELECT count(*) n FROM reports WHERE status='pending'",
            'familyLinks': 'SELECT count(*) n FROM guardian_links',
            'suspendedUsers': "SELECT count(*) n FROM account_status WHERE status='suspended'",
            'unverifiedUsers': 'SELECT count(*) n FROM users WHERE verified=0',
            'reportedUsers': "SELECT count(*) n FROM (SELECT p.user FROM reports r JOIN posts p ON p.id=r.target WHERE r.status='pending' UNION SELECT c.user FROM reports r JOIN comments c ON c.id=r.target WHERE r.status='pending' UNION SELECT u.id FROM reports r JOIN users u ON u.id=r.target WHERE r.status='pending')",
            'administrators': 'SELECT count(*) n FROM administrators',
            'connections': 'SELECT count(*)/2 n FROM contacts WHERE approved=1',
            'pendingConnections': "SELECT count(*) n FROM contact_requests WHERE status='pending' AND expires>strftime('%s','now')",
            'messages': 'SELECT count(*) n FROM messages',
            'unreadMessages': 'SELECT count(*) n FROM messages WHERE read=0',
            'comments': 'SELECT count(*) n FROM comments',
            'likes': 'SELECT count(*) n FROM likes',
            'activeStories': "SELECT count(*) n FROM posts WHERE story=1 AND expires>strftime('%s','now')",
            'expiredStories': "SELECT count(*) n FROM posts WHERE story=1 AND expires<=strftime('%s','now')",
            'pendingMediaUploads':'SELECT count(*) n FROM media_uploads',
            'pendingMediaDeletions':'SELECT count(*) n FROM media_deletions',
            'pendingMediaTransfers':'SELECT count(*) n FROM media_transfers',
            'cloudMedia':'SELECT count(*) n FROM media_objects',
            'mediaBytes': 'SELECT coalesce(sum(bytes),0) n FROM media_inventory',
            'feedViews': 'SELECT count(*) n FROM feed_views',
        }.items()}
        summary['categories']=repo.rows('SELECT c.category,count(*) count FROM post_categories c JOIN posts p ON p.id=c.post WHERE p.story=0 GROUP BY c.category ORDER BY count DESC')
        return summary
    if path == '/admin/users' and method == 'GET':
        status=data.get('status','all')
        if status not in ('all','active','suspended','unverified'): raise ApiError(400,'Situação inválida.')
        cursor=data.get('cursor','')
        if not isinstance(cursor,str) or len(cursor)>200: raise ApiError(400,'Cursor inválido.')
        conditions={'all':'1=1','active':"coalesce(s.status,'active')='active' AND u.verified=1",'suspended':"s.status='suspended'",'unverified':'u.verified=0'}
        rows=repo.rows('''SELECT u.id,u.name,u.email,u.verified,u.private,u.bio,
            coalesce(s.status,'active') status,pm.media avatar,
            EXISTS(SELECT 1 FROM administrators a WHERE a.user=u.id) isAdmin
            FROM users u LEFT JOIN account_status s ON s.user=u.id LEFT JOIN profile_media pm ON pm.user=u.id
            WHERE u.id>? AND '''+conditions[status]+' ORDER BY u.id LIMIT 31',(cursor,))
        return {'items':rows[:30],'nextCursor':rows[29]['id'] if len(rows)>30 else None}
    if path == '/admin/reports' and method == 'GET':
        rows = repo.rows('''SELECT r.id,r.target,r.reason,r.status,r.created,
            CASE WHEN p.id IS NOT NULL THEN 'post' WHEN c.id IS NOT NULL THEN 'comment' ELSE 'other' END targetType,
            coalesce(ctx.category,'other') category,coalesce(ctx.priority,1) priority,
            coalesce(ctx.target_type,'other') reportedType,
            coalesce(ctx.evidence,p.text,c.text) content
            FROM reports r LEFT JOIN posts p ON p.id=r.target
            LEFT JOIN comments c ON c.id=r.target LEFT JOIN report_context ctx ON ctx.report=r.id
            ORDER BY CASE WHEN r.status='pending' THEN 0 ELSE 1 END,coalesce(ctx.priority,1) DESC,r.created ASC,r.id ASC LIMIT 50''')
        return {'items': rows}
    parts = path.strip('/').split('/')
    if len(parts) == 3 and parts[:2] == ['admin', 'users'] and method == 'PATCH':
        target = repo.one('SELECT id FROM users WHERE id=?', (parts[2],))
        status = data.get('status')
        if status not in ('active', 'suspended'):
            raise ApiError(400, 'Situação inválida.')
        reason = text(data, 'reason', 3, 300)
        if not target:
            raise ApiError(404, 'Conta indisponível.')
        if target['id'] == actor['id'] or repo.one('SELECT 1 FROM administrators WHERE user=?', (target['id'],)):
            raise ApiError(403, 'Contas administrativas exigem revisão pelo operador do servidor.')
        repo.execute('INSERT OR REPLACE INTO account_status VALUES(?,?,?,?)', (target['id'],status,reason,time.time()))
        repo.execute('INSERT INTO account_moderation VALUES(?,?,?,?,?,?)', (token(),actor['id'],target['id'],status,reason,time.time()))
        service.audit('moderation.account.' + status, actor['id'])
        service.notification(target['id'], 'A situação da sua conta foi atualizada pela moderação. Consulte Privacidade e segurança.')
        return {'ok': True, 'status': status}
    if len(parts) == 3 and parts[:2] == ['admin', 'reports'] and method == 'PATCH':
        action = data.get('action')
        if action not in ('dismiss', 'remove'):
            raise ApiError(400, 'Decisão inválida.')
        reason = text(data,'reason',3,500) if 'reason' in data else ('Conteúdo removido após revisão da moderação.' if action=='remove' else 'Relato analisado e encerrado sem remoção do conteúdo.')
        report = repo.one('SELECT * FROM reports WHERE id=?', (parts[2],))
        if not report:
            raise ApiError(404, 'Denúncia indisponível.')
        if report['status'] != 'pending':
            raise ApiError(409, 'Esta denúncia já foi analisada.')
        post = repo.one('SELECT id,user FROM posts WHERE id=?', (report['target'],))
        comment = repo.one('SELECT id,user FROM comments WHERE id=?', (report['target'],))
        if action == 'remove' and not (post or comment):
            raise ApiError(400, 'Este alvo exige investigação manual. Apenas posts e comentários podem ser removidos aqui.')
        with repo.transaction():
            if action == 'remove':
                service.notification((post or comment)['user'], 'Um conteúdo seu foi removido após análise da moderação.')
                table = 'posts' if post else 'comments'
                repo.db.execute(f'DELETE FROM {table} WHERE id=?', (report['target'],))
            repo.db.execute('INSERT INTO report_decisions VALUES(?,?,?,?,?)', (report['id'],actor['id'],action,reason,time.time()))
            repo.db.execute('UPDATE reports SET status=? WHERE id=?', ('removed' if action == 'remove' else 'dismissed', report['id']))
            repo.db.execute('INSERT INTO notifications VALUES(?,?,?,?)', (token(), report['user'], 'Sua denúncia recebeu uma atualização.', time.time()))
            repo.db.execute('INSERT INTO audit VALUES(?,?,?,?)', (token(), 'moderation.' + action, digest(actor['id']), time.time()))
        return {'ok': True}
    raise ApiError(404, 'Recurso administrativo indisponível.')
