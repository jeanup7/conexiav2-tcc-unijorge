"""Prepare an isolated SQLite copy and external defines for native QA tests."""
import argparse
import json
from pathlib import Path
from backup import backup


def prepare(database, credentials, directory, port=8081):
    if not 1024 <= port <= 65535:
        raise ValueError('Use uma porta local entre 1024 e 65535.')
    saved=json.loads(Path(credentials).read_text(encoding='utf-8'))
    if saved.get('namespace')!='conexia-linked-pair-qa-v1':
        raise ValueError('Use somente o arquivo da dupla fictícia de QA.')
    guardian,child=saved['guardian'],saved['child']
    if any(not person['email'].endswith('@example.com') for person in (guardian,child)):
        raise ValueError('Não execute testes destrutivos com contas pessoais.')
    if not guardian['password'] or guardian['password']!=child['password']:
        raise ValueError('A dupla deve possuir a mesma senha de QA.')
    directory=Path(directory).resolve()
    if directory.exists():
        raise ValueError('Use um diretório novo para cada execução.')
    directory.mkdir(parents=True)
    copied=backup(database,directory/'test.sqlite3')
    target=directory/'qa-defines.json'
    target.write_text(json.dumps({
        'API_URL':f'http://127.0.0.1:{port}',
        'QA_GUARDIAN_EMAIL':guardian['email'],
        'QA_CHILD_EMAIL':child['email'],
        'QA_PASSWORD':guardian['password'],
        'QA_ISOLATED_DATABASE':True,
    }),encoding='utf-8')
    return copied,target


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('database','credentials','directory'):
        parser.add_argument('--'+name,required=True)
    parser.add_argument('--port',type=int,default=8081)
    args=parser.parse_args()
    prepare(args.database,args.credentials,args.directory,args.port)
    print('Banco isolado e configuração privada de QA preparados.')
