import unittest
import pytest
from domx_common import normalize_host, parse_tag_value

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

def test_parse_tag_value_happy_path():
    """Test correctly parsing existing tags from a semicolon-separated string."""
    record = "v=DMARC1; p=reject; rua=mailto:reports@example.com"
    assert parse_tag_value(record, "v") == "DMARC1"
    assert parse_tag_value(record, "p") == "reject"
    assert parse_tag_value(record, "rua") == "mailto:reports@example.com"

def test_parse_tag_value_missing_tag():
    """Test returning None when the specified tag is absent."""
    record = "v=DMARC1; p=reject"
    assert parse_tag_value(record, "rua") is None
    assert parse_tag_value(record, "sp") is None
    assert parse_tag_value(record, "x") is None
    assert parse_tag_value("", "p") is None

def test_parse_tag_value_edge_cases():
    """Test case insensitivity, whitespace handling, and malformed strings."""
    # Case insensitivity for tags
    record = "v=DMARC1; P=reject; RUA=mailto:reports@example.com"
    assert parse_tag_value(record, "p") == "reject"
    assert parse_tag_value(record, "P") == "reject"
    assert parse_tag_value(record, "rua") == "mailto:reports@example.com"

    # Whitespace handling
    record_spaces = "v=DMARC1;  p = reject ; rua=  mailto:reports@example.com  "
    assert parse_tag_value(record_spaces, "p") == "reject"
    assert parse_tag_value(record_spaces, "rua") == "mailto:reports@example.com"

    # Missing value
    assert parse_tag_value("p=", "p") is None

    # Ending with semicolon
    assert parse_tag_value("p=reject;", "p") == "reject"

if __name__ == '__main__':
    unittest.main()
