"""Exercise `hype generate` against a fake OpenAI-compatible endpoint: no network, no API key."""
import base64
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import threading
import unittest
import zlib
from http.server import BaseHTTPRequestHandler, HTTPServer

APP = Path(os.environ.get('HYPE_BIN') or Path(__file__).resolve().parents[1] / 'build/hype')

SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900"><rect width="1600" height="900" fill="#123456"/></svg>'
REPLY = f'''=== FILE: presentation.md ===
---
title: "Small Teams Ship Faster"
---

# Small teams ship faster

---

![span](hero.svg)

# Why

- Less coordination
- Faster decisions

=== FILE: images/hero.svg ===
```svg
{SVG}
```
=== FILE: ../evil.md ===
should never be written
=== FILE: images/notes.txt ===
not an svg
'''


def tiny_png():
    """A valid 2x2 red PNG, built without image libraries."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    row = b'\x00' + b'\xff\x00\x00' * 2
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(row * 2)) + chunk(b'IEND', b''))


DECK = '---\ntitle: "Deck"\n---\n\n# Alpha\n\n---\n\n# Beta\n\n- one\n- two\n\n---\n\n# Gamma\n'
SLIDE_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900"><rect width="1600" height="900" fill="#345"/></svg>'


class FakeEndpoint(BaseHTTPRequestHandler):
    reply = {'choices': [{'message': {'content': REPLY}, 'finish_reason': 'stop'}]}
    status = 200
    requests = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        FakeEndpoint.requests.append({'path': self.path, 'auth': self.headers.get('Authorization'), 'body': json.loads(body)})
        payload = json.dumps(FakeEndpoint.reply).encode()
        self.send_response(FakeEndpoint.status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


class EndpointCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        FakeEndpoint.requests = []
        FakeEndpoint.status = 200
        FakeEndpoint.reply = {'choices': [{'message': {'content': REPLY}, 'finish_reason': 'stop'}]}
        self.server = HTTPServer(('127.0.0.1', 0), FakeEndpoint)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.endpoint = f'http://127.0.0.1:{self.server.server_port}/v1/chat/completions'
        self.env = {key: value for key, value in os.environ.items()
                    if key not in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPE_AI_KEY', 'OPENROUTER_API_KEY')}
        self.env.update(QT_QPA_PLATFORM='offscreen', XDG_CONFIG_HOME=str(self.root / 'config'),
                        OMARCHY_PATH=str(self.root / 'omarchy'), HOME=str(self.root / 'home'))
        theme = self.root / 'omarchy/themes/paper'
        theme.mkdir(parents=True)
        (theme / 'colors.toml').write_text('background = "#ffffff"\nforeground = "#111111"\n')

    def hype(self, *arguments, code=0, **env):
        result = subprocess.run([str(APP), *map(str, arguments)], env={**self.env, **env}, cwd=self.root,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, code, result.stderr)
        return result


class GenerateTests(EndpointCase):
    def test_generate_writes_a_folder_with_slides_and_images(self):
        out = self.root / 'talk'
        result = self.hype('generate', 'a talk on small teams', '--endpoint', self.endpoint, '--model', 'test/model',
                           '--theme', 'paper', '-o', out, '--json', HYPE_AI_KEY='sk-test')
        report = json.loads(result.stdout)
        self.assertEqual(report['presentation'], str(out / 'presentation.md'))
        self.assertEqual(report['warnings'], [])
        text = (out / 'presentation.md').read_text()
        self.assertIn('title: "Small Teams Ship Faster"', text)
        self.assertIn('color_background: "#ffffff"', text)  # The chosen theme was applied.
        self.assertEqual((out / 'images/hero.svg').read_text().strip(), SVG)  # Code fence stripped.
        self.assertTrue((out / 'videos').is_dir())
        self.assertFalse((self.root / 'evil.md').exists() or (out / 'images/notes.txt').exists())
        self.assertEqual(json.loads(self.hype('check', out / 'presentation.md', '--json').stdout)['problems'], [])
        request = FakeEndpoint.requests[0]
        self.assertEqual(request['auth'], 'Bearer sk-test')
        self.assertEqual(request['body']['model'], 'test/model')
        system, user = request['body']['messages']
        self.assertIn('hype check', system['content'])  # The format guide was inlined.
        self.assertNotIn('{{format}}', system['content'])
        self.assertEqual(user['content'], 'a talk on small teams')

    def test_generate_names_the_folder_after_the_title_without_overwriting(self):
        root = Path(self.env['HOME']) / 'Documents/Hype'
        for expected in ('small-teams-ship-faster', 'small-teams-ship-faster-2'):
            report = json.loads(self.hype('generate', 'x', '--endpoint', self.endpoint, '--json').stdout)
            self.assertEqual(report['presentation'], str(root / expected / 'presentation.md'))

    def test_generate_refuses_a_non_empty_folder(self):
        (self.root / 'taken').mkdir()
        (self.root / 'taken/keep.txt').write_text('mine')
        error = self.hype('generate', 'x', '--endpoint', self.endpoint, '-o', self.root / 'taken', code=1).stderr
        self.assertIn('not empty', error)
        self.assertEqual((self.root / 'taken/keep.txt').read_text(), 'mine')

    def test_generate_needs_a_key_for_a_remote_endpoint(self):
        error = self.hype('generate', 'x', '--endpoint', 'https://example.invalid/v1/chat/completions', code=1).stderr
        self.assertIn('OPENROUTER_API_KEY', error)
        self.assertEqual(FakeEndpoint.requests, [])
        self.hype('generate', 'x', '--endpoint', 'not a url', code=1, OPENROUTER_API_KEY='k')

    def test_generate_reports_endpoint_errors_and_bad_replies(self):
        FakeEndpoint.status = 401
        FakeEndpoint.reply = {'error': {'message': 'Invalid API key'}}
        self.assertIn('HTTP 401: Invalid API key', self.hype('generate', 'x', '--endpoint', self.endpoint, code=1).stderr)
        FakeEndpoint.status = 200
        FakeEndpoint.reply = {'choices': [{'message': {'content': 'Sure! Here is a talk.'}, 'finish_reason': 'stop'}]}
        self.assertIn('presentation.md', self.hype('generate', 'x', '--endpoint', self.endpoint, code=1).stderr)
        FakeEndpoint.reply = {'choices': [{'message': {'content': REPLY}, 'finish_reason': 'length'}]}
        self.assertIn('ran out of output tokens', self.hype('generate', 'x', '--endpoint', self.endpoint, code=1).stderr)

    def test_generate_warns_about_images_the_model_forgot_to_write(self):
        FakeEndpoint.reply = {'choices': [{'message': {'content': '---\ntitle: "T"\n---\n\n# One\n\n---\n\n![](missing.svg)\n'},
                                           'finish_reason': 'stop'}]}
        report = json.loads(self.hype('generate', 'x', '--endpoint', self.endpoint, '-o', self.root / 't', '--json').stdout)
        self.assertEqual(len(report['warnings']), 1)
        self.assertIn('Slide 2', report['warnings'][0])

    def test_saved_settings_and_custom_template(self):
        template = self.root / 'mine.md'
        template.write_text('Custom instructions.\n\n{{format}}\n')
        self.hype('generate', '--save', '--endpoint', self.endpoint, '--model', 'saved/model', '--template', template)
        self.hype('generate', 'x', '-o', self.root / 'a', HYPE_AI_KEY='k')  # Endpoint, model and template come from settings.
        body = FakeEndpoint.requests[0]['body']
        self.assertEqual(body['model'], 'saved/model')
        self.assertTrue(body['messages'][0]['content'].startswith('Custom instructions.'))
        self.assertIn('Custom instructions.', self.hype('generate', '--print-template').stdout)

    def test_mind_map_flag_adds_the_outline_rules(self):
        outline = 'Talk\n  Why\n    Speed\n  How\n'
        self.hype('generate', outline, '--mind-map', '--endpoint', self.endpoint, '-o', self.root / 'm', HYPE_AI_KEY='k')
        system, user = FakeEndpoint.requests[0]['body']['messages']
        self.assertIn('The brief is a mind map', system['content'])
        self.assertIn('OPML', system['content'])
        self.assertEqual(user['content'], outline.strip())
        self.hype('generate', 'a talk', '--endpoint', self.endpoint, '-o', self.root / 'p', HYPE_AI_KEY='k')
        self.assertNotIn('The brief is a mind map', FakeEndpoint.requests[1]['body']['messages'][0]['content'])
        self.assertIn('The brief is a mind map', self.hype('generate', '--print-template', '--mind-map').stdout)
        self.assertIn('Paste your mind map', self.hype('generate', ' ', '--mind-map', '--endpoint', self.endpoint, code=1).stderr)

    def test_print_template_shows_the_bundled_prompt(self):
        text = self.hype('generate', '--print-template').stdout
        self.assertIn('=== FILE: presentation.md ===', text)
        self.assertIn('Writing a Hype presentation', text)


class ReviseTests(EndpointCase):
    """hype revise: one slide changed by the model, everything else left exactly as it was."""

    def setUp(self):
        super().setUp()
        self.deck = self.root / 'deck/presentation.md'
        self.deck.parent.mkdir()
        self.deck.write_text(DECK)

    def reply(self, content):
        FakeEndpoint.reply = {'choices': [{'message': {'content': content}, 'finish_reason': 'stop'}]}

    def revise(self, *arguments, code=0):
        return self.hype('revise', self.deck, 2, 'make it punchier', '--endpoint', self.endpoint, *arguments,
                         code=code, HYPE_AI_KEY='k')

    def test_text_rewrites_only_the_chosen_slide_and_sends_the_outline(self):
        self.reply('```markdown\n# Punchy\n\n- Fast\n- Simple\n```')
        result = json.loads(self.revise('--json').stdout)
        self.assertEqual(result['slide'], 2)
        self.assertEqual(self.deck.read_text(), DECK.replace('# Beta\n\n- one\n- two', '# Punchy\n\n- Fast\n- Simple'))
        system, user = FakeEndpoint.requests[0]['body']['messages']
        self.assertIn('one slide', system['content'])
        self.assertIn('1. Alpha', user['content'])
        self.assertIn('2. Beta   <- the slide to change', user['content'])
        self.assertIn('3. Gamma', user['content'])
        self.assertIn('- one\n- two', user['content'])
        self.assertTrue(user['content'].endswith('Request: make it punchier'))
        self.assertTrue(list((self.deck.parent / '.hype-backups').glob('presentation.md.*')))  # The old version is kept.

    def test_a_reply_with_several_slides_is_refused(self):
        self.reply('# One\n\n---\n\n# Two')
        self.assertIn('more than one slide', self.revise(code=1).stderr)
        self.reply('```\n---\n# Two\n```')  # A whole reply that is one fence is still a single slide.
        self.assertEqual(self.deck.read_text(), DECK)

    def test_a_code_fence_may_contain_a_separator(self):
        self.reply('# Code\n\n````\n---\n````')
        self.revise()
        self.assertIn('````\n---\n````', self.deck.read_text())
        self.assertEqual(json.loads(self.hype('check', self.deck, '--json').stdout)['slides'], 3)

    def test_diagram_writes_an_svg_and_never_overwrites_one(self):
        self.reply(f'=== FILE: slide.md ===\n# Flow\n\n![right](flow.svg)\n=== FILE: images/flow.svg ===\n{SLIDE_SVG}\n')
        result = json.loads(self.revise('--diagram', '--json').stdout)
        self.assertEqual(result['warnings'], [])
        self.assertIn('![right](flow.svg)', self.deck.read_text())
        self.assertEqual((self.deck.parent / 'images/flow.svg').read_text().strip(), SLIDE_SVG)
        self.assertEqual(json.loads(self.hype('check', self.deck, '--json').stdout)['problems'], [])
        self.assertIn('slide.md', FakeEndpoint.requests[0]['body']['messages'][0]['content'])
        self.reply(f'=== FILE: slide.md ===\n# Flow\n\n![right](flow.svg)\n=== FILE: images/flow.svg ===\n{SLIDE_SVG}\n')
        self.revise('--diagram')  # A second picture with the same name goes beside the first.
        self.assertTrue((self.deck.parent / 'images/flow-2.svg').exists())
        self.assertIn('![right](flow-2.svg)', self.deck.read_text())
        self.assertIn('fill="#345"', (self.deck.parent / 'images/flow.svg').read_text())

    def test_image_adds_a_picture_beside_the_text(self):
        data = 'data:image/png;base64,' + base64.b64encode(tiny_png()).decode()
        FakeEndpoint.reply = {'choices': [{'message': {'content': '', 'images': [{'image_url': {'url': data}}]}}]}
        self.hype('revise', self.deck, 2, 'A calm sunrise', '--image', '--endpoint', self.endpoint,
                  '--image-model', 'img/model', HYPE_AI_KEY='k')
        request = FakeEndpoint.requests[0]['body']
        self.assertEqual(request['model'], 'img/model')
        self.assertEqual(request['modalities'], ['image', 'text'])
        self.assertIn('Beta', request['messages'][0]['content'])
        self.assertIn('A calm sunrise', request['messages'][0]['content'])
        self.assertTrue((self.deck.parent / 'images/a-calm-sunrise.png').read_bytes().startswith(b'\x89PNG'))
        text = self.deck.read_text()
        self.assertIn('# Beta\n\n- one\n- two\n![right](a-calm-sunrise.png)', text)  # The text is untouched.
        self.assertEqual(json.loads(self.hype('check', self.deck, '--json').stdout)['problems'], [])

    def test_image_endpoint_may_be_the_images_api(self):
        FakeEndpoint.reply = {'data': [{'b64_json': base64.b64encode(tiny_png()).decode()}]}
        self.hype('revise', self.deck, 1, 'A logo', '--image', '--endpoint', self.endpoint, '--image-endpoint',
                  self.endpoint.replace('/chat/completions', '/images/generations'), HYPE_AI_KEY='k')
        request = FakeEndpoint.requests[0]
        self.assertTrue(request['path'].endswith('/images/generations'))
        self.assertIn('A logo', request['body']['prompt'])
        self.assertNotIn('messages', request['body'])
        self.assertIn('# Alpha\n![right](a-logo.png)', self.deck.read_text())  # A headline counts as text, so the picture goes beside it.

    def test_image_errors(self):
        FakeEndpoint.reply = {'choices': [{'message': {'content': 'I cannot draw.'}}]}
        self.assertIn('no picture', self.hype('revise', self.deck, 2, 'x', '--image', '--endpoint', self.endpoint,
                                               code=1, HYPE_AI_KEY='k').stderr)
        FakeEndpoint.reply = {'choices': [{'message': {'images': [{'image_url': {'url': 'data:image/png;base64,AAAA'}}]}}]}
        self.assertIn('not a picture', self.hype('revise', self.deck, 2, 'x', '--image', '--endpoint', self.endpoint,
                                                  code=1, HYPE_AI_KEY='k').stderr)
        self.assertEqual(self.deck.read_text(), DECK)
        self.assertFalse((self.deck.parent / 'images').exists() and any((self.deck.parent / 'images').iterdir()))

    def test_argument_errors_leave_the_deck_alone(self):
        self.assertIn('1 to 3', self.hype('revise', self.deck, 9, 'x', '--endpoint', self.endpoint, code=1).stderr)
        self.assertIn('either', self.revise('--diagram', '--image', code=1).stderr)
        self.assertIn('Say what', self.hype('revise', self.deck, 2, ' ', '--endpoint', self.endpoint, code=1).stderr)
        self.assertEqual(FakeEndpoint.requests, [])
        FakeEndpoint.status = 500
        FakeEndpoint.reply = {'error': {'message': 'Model overloaded'}}
        self.assertIn('HTTP 500: Model overloaded', self.revise(code=1).stderr)
        self.assertEqual(self.deck.read_text(), DECK)

    def test_help_lists_revise(self):
        self.assertIn('revise', self.hype('help').stdout)
        self.assertIn('--diagram', self.hype('help', 'revise').stdout)


if __name__ == '__main__':
    unittest.main()
