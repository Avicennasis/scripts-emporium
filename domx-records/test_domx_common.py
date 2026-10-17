import unittest
from domx_common import normalize_host

class TestNormalizeHost(unittest.TestCase):
    def test_normalize_host_none(self):
        self.assertEqual(normalize_host(None), '')

    def test_normalize_host_empty_string(self):
        self.assertEqual(normalize_host(''), '')
        self.assertEqual(normalize_host('   '), '')

    def test_normalize_host_mixed_case(self):
        self.assertEqual(normalize_host('Mail.Example.COM'), 'mail.example.com')
        self.assertEqual(normalize_host('EXAMPLE.COM'), 'example.com')

    def test_normalize_host_trailing_dots(self):
        self.assertEqual(normalize_host('mail.example.com.'), 'mail.example.com')
        self.assertEqual(normalize_host('example.com.'), 'example.com')

    def test_normalize_host_mixed_case_and_trailing_dots(self):
        self.assertEqual(normalize_host('Mail.Example.COM.'), 'mail.example.com')
        self.assertEqual(normalize_host('  EXAMPLE.COM.  '), 'example.com')

if __name__ == '__main__':
    unittest.main()
