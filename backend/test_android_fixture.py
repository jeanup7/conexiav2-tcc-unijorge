import json
import tempfile
import unittest
from pathlib import Path
from repository import Repository
from prepare_android_test import prepare


class AndroidFixtureTests(unittest.TestCase):
    def test_fixture_is_separate_and_cannot_overwrite_a_previous_run(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            source=root/'original.sqlite3'
            repo=Repository(str(source))
            repo.execute("INSERT INTO users(id,email,password,name,birth) VALUES('qa','qa@example.com','unused','QA','1990-01-01')")
            repo.db.close()
            credentials=root/'credentials.json'
            payload={'namespace':'conexia-linked-pair-qa-v1','guardian':{'email':'g@example.com','password':'test password'},'child':{'email':'c@example.com','password':'test password'}}
            credentials.write_text(json.dumps(payload),encoding='utf-8')
            copied,config=prepare(source,credentials,root/'run')
            local=Repository(str(copied))
            local.execute("DELETE FROM users WHERE id='qa'")
            local.db.close()
            original=Repository(str(source))
            self.assertIsNotNone(original.one("SELECT id FROM users WHERE id='qa'"))
            original.db.close()
            defines=json.loads(config.read_text(encoding='utf-8'))
            self.assertTrue(defines['QA_ISOLATED_DATABASE'])
            self.assertEqual('http://127.0.0.1:8081',defines['API_URL'])
            with self.assertRaises(ValueError):prepare(source,credentials,root/'run')
            payload['child']['email']='personal@gmail.com'
            credentials.write_text(json.dumps(payload),encoding='utf-8')
            with self.assertRaises(ValueError):prepare(source,credentials,root/'another-run')
            self.assertFalse((root/'another-run').exists())

    def test_integration_mode_never_executes_external_identity_deletions(self):
        from service import Service
        class Identity:
            def delete(self,uid):raise AssertionError('Remote identity deletion is forbidden in integration mode')
        repo=Repository(':memory:')
        try:
            repo.execute("INSERT INTO identity_deletions(uid,created) VALUES('pending-private-identity',1)")
            service=Service(repo,development=True,firebase=Identity(),integration_test=True)
            service.process_identity_deletions()
            self.assertIsNone(repo.one("SELECT completed FROM identity_deletions")['completed'])
            self.assertTrue(service.dispatch('GET','/health',{})['isolatedIntegration'])
            with self.assertRaises(ValueError):Service(repo,development=False,integration_test=True)
        finally:repo.db.close()
