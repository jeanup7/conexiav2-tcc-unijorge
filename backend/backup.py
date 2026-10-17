"""Consistent SQLite backup, including committed WAL data."""
import argparse
import os
import sqlite3
from pathlib import Path
from urllib.parse import quote


def backup(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if not source.is_file() or source == destination or destination.exists():
        raise ValueError('Use um banco existente e um destino novo, diferente da origem.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation prevents overwriting an existing backup.
    descriptor = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)
    src = sqlite3.connect('file:'+quote(source.as_posix(), safe='/:')+'?mode=ro', uri=True)
    dst = sqlite3.connect(destination)
    try:
        src.backup(dst)
        if dst.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
            raise RuntimeError('A verificação do backup falhou.')
    finally:
        src.close()
        dst.close()
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    backup(args.source, args.output)
    print('Backup concluído e verificado. Guarde-o em armazenamento protegido.')
