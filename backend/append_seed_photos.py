"""Append newly catalogued photos to an existing QA seed without resetting it."""
import json
import os
import time
from pathlib import Path

from backup import backup
from repository import Repository
from seed_data import ROOT, SeedConfig, Seeder


def main():
    if os.environ.get('CONEXIA_DEV') != '1':
        raise SystemExit('Use CONEXIA_DEV=1 para alterar apenas o seed local.')
    path = ROOT / 'conexia.sqlite3'
    backup(path, Path.home() / 'Documents' / 'Conexia-backups' /
           f'before-photos-{int(time.time()*1000)}.sqlite3')
    repo = Repository(str(path))
    try:
        config = SeedConfig()
        seed = Seeder(repo, config)
        row = repo.one('SELECT manifest FROM seed_runs WHERE namespace=?', (config.namespace,))
        if not row:
            raise SystemExit('Execute o seed principal antes de adicionar fotos.')
        manifest = json.loads(row['manifest'])
        added = []
        with repo.transaction():
            for index in range(manifest['suppliedImages'], len(seed.catalog)):
                owner = seed.identifier('user', index)
                avatar = repo.one('SELECT media FROM profile_media WHERE user=?', (owner,))
                if not avatar:
                    raise ValueError('Perfil fictício correspondente não encontrado.')
                content = seed.normalized[index]
                repo.db.execute('UPDATE media SET mime=?,data=? WHERE id=? AND user=?',
                                ('image/jpeg', content, avatar['media'], owner))
                item = seed.catalog[index]
                mid = seed.add_media(owner, content, 'supplement', index, index)
                pid = seed.identifier('post-supplement', index)
                caption = ('Explorando novas ideias: um retrato cheio de personalidade. '
                           'Qual detalhe você mais gostou? #ilustração #criatividade'
                           if item['file'] == 'zeno_kamau.jpg' else
                           'Do rascunho à história: experimentando traços em preto e branco. '
                           'Que aventura você criaria para esse personagem? #desenho #quadrinhos')
                created = seed.now - (index - manifest['suppliedImages']) * 30
                seed.insert('posts', (pid, owner, caption, mid, 0, created, None))
                seed.insert('post_media', (pid, mid, 0))
                seed.insert('post_categories', (pid, item['category']))
                for entry in manifest['media']:
                    if entry['id'] == avatar['media']:
                        entry.update(source=item['file'], placeholderUrl=None)
                added.append(dict(id=pid, user=owner, text=caption, category=item['category'],
                                  story=False, created=created, expires=None, mediaItems=[mid]))
            manifest['media'].extend(seed.media)
            manifest['posts'] = added + manifest['posts']
            manifest['counts']['posts'] += len(added)
            manifest['counts']['media'] += len(seed.media)
            manifest['suppliedImages'] = len(seed.catalog)
            if repo.db.execute('PRAGMA foreign_key_check').fetchall():
                raise ValueError('Referências inválidas; inclusão cancelada.')
            repo.db.execute('UPDATE seed_runs SET manifest=? WHERE namespace=?',
                            (json.dumps(manifest, ensure_ascii=False), config.namespace))
        (ROOT / 'fixtures' / 'seed_manifest.json').write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({'postsAdded': len(added), 'avatarsUpdated': len(added),
                          'suppliedImages': manifest['suppliedImages']}, ensure_ascii=False))
    finally:
        repo.db.close()


if __name__ == '__main__':
    main()
