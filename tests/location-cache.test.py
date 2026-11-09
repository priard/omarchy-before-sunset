import json, os, pathlib, subprocess, tempfile, unittest
SCRIPT = pathlib.Path(__file__).resolve().parent.parent / 'bin/before-sunset-auto-location'
class CacheTest(unittest.TestCase):
    def test_cache_validation_and_transport_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            p=pathlib.Path(directory); (p/'bin').mkdir()
            curl=p/'bin/curl'
            env=dict(os.environ, HOME=directory, PATH=str(p/'bin')+':/usr/bin')
            def run(payload, status=0):
                curl.write_text('#!/usr/bin/python3\nimport sys\nsys.stdout.write('+repr(payload)+')\nsys.exit('+str(status)+')\n')
                curl.chmod(0o755)
                return json.loads(subprocess.check_output([SCRIPT],env=env))
            valid='{"name":"Example","latitude":40.7,"longitude":-74.0}'
            self.assertEqual(run('',1),dict(fresh=False,location=None))
            result=run(valid); self.assertTrue(result['fresh'])
            cached=result['location']
            for malformed in ['{}','{"latitude":91,"longitude":0}', '{"latitude":"40.7","longitude":0}', valid+'\n'+valid, '<html>error</html>']:
                self.assertEqual(run(malformed),dict(fresh=False,location=cached))
            # Even syntactically valid partial output from a failed curl must not replace cache.
            self.assertEqual(run('{"latitude":1,"longitude":2}',18),dict(fresh=False,location=cached))
            cache=p/'.cache/omarchy/before-sunset-location.json'
            cache.write_text('corrupt')
            self.assertEqual(run('',1),dict(fresh=False,location=None))
            self.assertEqual(list(cache.parent.glob('*.XXXXXX')),[])
if __name__=='__main__': unittest.main()
