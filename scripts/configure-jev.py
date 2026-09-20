#!/usr/bin/env python3
"""Set up Jev locally; never pass the API key through argv or chat."""
import getpass
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


def main():
    os.umask(0o077)
    home = Path.home()
    runtime = home / '.local/share/attention-log'
    config_path = runtime / 'config.json'
    jobs = [home / 'Library/LaunchAgents' / f'com.attention-log.{name}.plist'
            for name in ('collector', 'digest')]
    config = json.loads(config_path.read_text())
    definitions = [plistlib.loads(p.read_bytes()) for p in jobs]
    if not sys.stdin.isatty():
        raise SystemExit('Uruchom to polecenie w interaktywnym terminalu.')
    print('Konfiguracja Jev / TypeSafe. Podsumowania pozostają lokalne.')
    print('Jev otrzyma tytuły, domeny, fragmenty do 2000 znaków i wskaźniki uwagi.')
    key = getpass.getpass('Klucz API TypeSafe (niewidoczny podczas wpisywania): ').strip()
    if not key or any(c.isspace() for c in key) or any(c in key for c in '\"\'\\$`#'):
        raise SystemExit('Niepoprawny format klucza. Nic nie zmieniono.')
    secret = runtime / 'typesafe.env'
    secret.write_text('TYPESAFE_API_KEY=' + key + '\n')
    secret.chmod(0o600)
    for path, definition in zip(jobs, definitions):
        args = [a for a in definition['ProgramArguments']
                if not a.startswith('--env-file=')]
        args.insert(1, '--env-file=' + str(secret))
        definition['ProgramArguments'] = args
        path.write_bytes(plistlib.dumps(definition))
        path.chmod(0o600)
    config['jevEnabled'] = True
    config_path.write_text(json.dumps(config, indent=2) + '\n')
    config_path.chmod(0o600)
    domain = f'gui/{os.getuid()}'
    for path, definition in zip(jobs, definitions):
        subprocess.run(['launchctl', 'bootout', domain + '/' + definition['Label']],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['launchctl', 'bootstrap', domain, str(path)], check=True)
    print('Klucz zapisany lokalnie (uprawnienia 600). Jev włączony, serwis przeładowany.')
    print('Poprawność klucza zostanie sprawdzona przy klasyfikacji kwalifikującej się strony.')


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        raise SystemExit('\nAnulowano wpisywanie klucza.')
