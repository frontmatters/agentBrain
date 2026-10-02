#!/usr/bin/env python3
"""Exercise the actual Claude hook contract, never shipping literal credentials."""
import base64
import json
import os
import secrets
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

ADDON = Path(__file__).resolve().parents[1]
GUARD = ADDON / 'claude-pretooluse-secret-guard.py'


class GuardTests(unittest.TestCase):
    def invoke(self, value, tool='Bash'):
        payload = {'tool_name': tool, 'tool_input': {'command': value}}
        return subprocess.run(['python3', str(GUARD)], input=json.dumps(payload), text=True, capture_output=True)

    def test_block(self):
        # Non-repeating synthetic values avoid a literal usable key in the repo.
        opaque = secrets.token_hex(24)
        samples = {
            'token hex': 'token ' + 'a' * 40,
            'authorization': 'Authorization: Bearer ' + 'aB3_' * 12,
            'github classic': 'ghp_' + opaque[:36],
            'github oauth': 'gho_' + opaque[:36],
            'github server': 'ghs_' + opaque[:36],
            'github user': 'ghu_' + opaque[:36],
            'github fine': 'github_pat_' + opaque[:22] + '_' + secrets.token_hex(30)[:59],
            'anthropic': 'sk-' + 'ant-api03-' + opaque + secrets.token_hex(24),
            'openai project': 'sk-proj-' + opaque,
            'openai legacy': 'sk-' + opaque,
            'slack': 'xoxb-' + '1234567890-' * 4,
            'aws': 'AKIA' + 'A' * 16,
            'private key': '-----BEGIN RSA PRIVATE' + ' KEY-----\n' + 'a' * 50,
            'url': 'https://example.invalid/path?password=' + opaque,
            'url userinfo': 'git clone https://someone:' + opaque[:24] + '@example.invalid/x.git',
            'url short password': 'https://someone:hunter2x@example.invalid/x.git',
            'url eight-character password': 'https://someone:ab3d5f7h@example.invalid/x.git',
            'export token': 'export GITEA_TOKEN=' + opaque,
            'api key assignment': 'API_KEY="' + opaque[:32] + '"',
            'mixed alphanumeric assignment': 'API_KEY=' + opaque[:30] + '9B',
            'long letters assignment': 'API_KEY=' + 'AbCdEfGhIjKlMnOpQrStUvWxYzAbCdEfGhIjKl',
            'password mapping': 'password: ' + opaque[:24],
            'secret assignment': 'CLIENT_SECRET=' + opaque,
            'passwd assignment': 'DB_PASSWD=' + opaque,
            'apikey assignment': 'APIKEY=' + opaque,
            'curl basic short': 'curl -u user:' + opaque[:12] + ' https://example.invalid',
            'curl basic long': 'curl --user user:' + opaque[:12] + ' https://example.invalid',
            'authorization basic': 'Authorization: Basic ' + base64.b64encode(secrets.token_bytes(24)).decode(),
        }
        for kind, value in samples.items():
            for tool in ('Bash', 'Write', 'mcp__brain_save_learning'):
                with self.subTest(kind=kind, tool=tool):
                    proc = self.invoke(value, tool)
                    self.assertEqual(proc.returncode, 2, proc.stderr)
                    self.assertIn('Blocked:', proc.stderr)
                    self.assertFalse(value in proc.stderr, 'diagnostic echoed input')
                    self.assertEqual(proc.stdout, '')

    def test_allow(self):
        samples = [
            'token', 'password', 'Use a token from the vault',
            'Bearer $TOKEN', 'Authorization: Bearer ${X}',
            'Authorization: Bearer $(secrets get access)',
            'token ' + '$TOKEN', '<token>', 'xxx', 'ghp_xxxxxxxx...',
            'a' * 40, 'git show ' + 'a' * 40,
            'https://example.invalid/?token=$TOKEN',
            'https://example.invalid/?password=<token>',
            'ssh://git@example.invalid/x.git',
            'token = self.access_token_value', 'secret: session-name-for-tests',
            'CLIENT_SECRET=config.client_secret',
            'https://$USER:$TOKEN@example.invalid/x.git',
            'https://someone:<password>@example.invalid/x.git',
            'https://someone:password@example.invalid/x.git',
            'export GITEA_TOKEN=$TOKEN',
            'API_KEY="$(secrets get my-key)"',
            'password: <token>',
            'DB_PASSWD=/opt/secure/password-file',
            'GITEA_TOKEN_FROM=keychain:GITEA_API_KEY@~/Library/example',
            'token: some_variable_name',
            'CLIENT_SECRET=ANOTHER_VARIABLE_ID',
            'API_KEY=shortnamewithoutdigits',
            'curl -u "$U:$P" https://example.invalid',
            'sk-' + 'x' * 48,
            'ghp_' + 'x' * 36,
        ]
        for index, value in enumerate(samples):
            with self.subTest(case=index):
                self.assertEqual(self.invoke(value).returncode, 0)

    def test_nested_fields(self):
        payload = {'tool_input': {'outer': [{'content': 'AKIA' + 'A' * 16}]}}
        proc = subprocess.run(['python3', str(GUARD)], input=json.dumps(payload), text=True, capture_output=True)
        self.assertEqual(proc.returncode, 2)
        self.assertNotIn('AKIA', proc.stderr)
        payload = {'tool_input': {'headers': {'Authorization': 'Bearer ' + 'a' * 32}}}
        proc = subprocess.run(['python3', str(GUARD)], input=json.dumps(payload), text=True, capture_output=True)
        self.assertEqual(proc.returncode, 2)
        self.assertNotIn('a' * 32, proc.stderr)
        payload = {'tool_input': {'headers': {'Authorization': 'Basic ' + base64.b64encode(secrets.token_bytes(24)).decode()}}}
        proc = subprocess.run(['python3', str(GUARD)], input=json.dumps(payload), text=True, capture_output=True)
        self.assertEqual(proc.returncode, 2)

    def test_install_uninstall_isolated_home(self):
        with tempfile.TemporaryDirectory() as root:
            home = str(Path(root) / 'home')
            Path(home).mkdir()
            # Execute the addon from a path with spaces, still isolated from real HOME.
            addon = Path(root) / 'test addon'
            shutil.copytree(ADDON, addon)
            env = {**os.environ, 'HOME': home}
            settings = Path(home) / '.claude/settings.json'
            for script in ('install.sh', 'install.sh'):
                subprocess.run(['bash', str(addon / script)], env=env, check=True, capture_output=True)
            data = json.loads(settings.read_text())
            self.assertEqual(len(data['hooks']['PreToolUse']), 1)
            command = data['hooks']['PreToolUse'][0]['hooks'][0]['command']
            self.assertEqual(command, 'python3 "' + str(addon / 'claude-pretooluse-secret-guard.py') + '"')
            data['hooks']['PreToolUse'].append({'matcher': 'Read', 'hooks': [{'type': 'command', 'command': 'other-guard'}]})
            data['other'] = {'keep': True}
            settings.write_text(json.dumps(data))
            subprocess.run(['bash', str(addon / 'uninstall.sh')], env=env, check=True, capture_output=True)
            data = json.loads(settings.read_text())
            self.assertEqual(data['hooks']['PreToolUse'], [{'matcher': 'Read', 'hooks': [{'type': 'command', 'command': 'other-guard'}]}])
            self.assertEqual(data['other'], {'keep': True})
            # A pre-existing settings file is merged without overwriting its hooks.
            settings.write_text(json.dumps(data))
            subprocess.run(['bash', str(addon / 'install.sh')], env=env, check=True, capture_output=True)
            data = json.loads(settings.read_text())
            self.assertEqual(len(data['hooks']['PreToolUse']), 2)
            self.assertEqual(data['other'], {'keep': True})


if __name__ == '__main__':
    unittest.main()
