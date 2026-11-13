import os
import sys
import unittest
from unittest.mock import patch, MagicMock

import json
from pathlib import Path

# Ensure we can import main
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
import main
from main import extract_post_text, is_same_site, load_seen, compile_keyword_regex, listing_id_from_url

def test_listing_id_from_url_normal():
    url = "https://boston.craigslist.org/gbs/gms/d/waltham-title/7812345678.html"
    assert listing_id_from_url(url) == "7812345678"

def test_listing_id_from_url_with_query():
    url = "https://boston.craigslist.org/gbs/gms/d/waltham-title/7812345678.html?foo=bar"
    assert listing_id_from_url(url) == "7812345678"

def test_listing_id_from_url_fallback_no_numeric():
    url = "https://boston.craigslist.org/gbs/gms/d/waltham-title/abc.html"
    assert listing_id_from_url(url) == url

def test_listing_id_from_url_fallback_no_html():
    url = "https://boston.craigslist.org/gbs/gms/d/waltham-title/7812345678"
    assert listing_id_from_url(url) == url

def test_is_same_site_normal():
    assert is_same_site("https://sfbay.craigslist.org/zip/123.html", "https://sfbay.craigslist.org") is True
    assert is_same_site("https://newyork.craigslist.org/zip/123.html", "https://sfbay.craigslist.org") is False

def test_is_same_site_exception():
    # Feeding an integer to urlparse triggers an AttributeError (which inherits from Exception)
    # The function should catch it and return False
    assert is_same_site(123, "https://sfbay.craigslist.org") is False
    assert is_same_site("https://sfbay.craigslist.org", 123) is False

def test_extract_post_text_normal():
    html = '<html><body><section id="postingbody">This is a test post.</section></body></html>'
    assert extract_post_text(html) == "This is a test post."

def test_extract_post_text_boilerplate():
    html = '<html><body><section id="postingbody">QR Code Link to This Post  \n  Real content here.</section></body></html>'
    assert extract_post_text(html) == "Real content here."

def test_extract_post_text_missing():
    html = '<html><body><div>No posting body.</div></body></html>'
    assert extract_post_text(html) == ""

def test_compile_keyword_regex_normal():
    regex = compile_keyword_regex(["apple", "banana", "cherry"])
    assert regex.search("I want an apple")
    assert regex.search("BANANA is good")
    assert not regex.search("I like pear")

def test_compile_keyword_regex_empty():
    regex = compile_keyword_regex([])
    assert not regex.search("apple")
    assert not regex.search("")

    regex_whitespace = compile_keyword_regex([" ", "\t"])
    assert not regex_whitespace.search("apple")
    assert not regex_whitespace.search("")

def test_compile_keyword_regex_special_characters():
    regex = compile_keyword_regex(["C++", "Node.js", "C#"])
    assert regex.search("I code in C++")
    assert regex.search("Using Node.js is fun")
    assert regex.search("Learning C#")
    assert not regex.search("I code in C+")
    assert not regex.search("Using NodeXjs")

def test_compile_keyword_regex_case_insensitive():
    regex = compile_keyword_regex(["Python"])
    assert regex.search("python")
    assert regex.search("PYTHON")
    assert regex.search("pYtHoN")

def test_save_seen_normal(tmp_path: Path):
    path = tmp_path / "seen.json"
    seen = {"id1": None, "id2": None, "id3": None}

    main.save_seen(path, seen)

    assert path.exists()

    with open(path, "r") as f:
        data = json.load(f)

    assert data == ["id1", "id2", "id3"]

def test_save_seen_truncates(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(main, "MAX_SEEN_ENTRIES", 2)
    path = tmp_path / "seen.json"
    # Dictionaries maintain insertion order in python 3.7+
    seen = {"id1": None, "id2": None, "id3": None, "id4": None}

    main.save_seen(path, seen)

    with open(path, "r") as f:
        data = json.load(f)

    assert data == ["id3", "id4"]


def test_load_seen_invalid_json(tmp_path):
    path = tmp_path / "invalid.json"
    path.write_text("invalid json", encoding="utf-8")
    assert main.load_seen(path) == {}


class TestSendAlert(unittest.TestCase):
    @patch('main.subprocess.run')
    @patch('main.shutil.which')
    @patch.dict(os.environ, {"ALERT_TO": "test@example.com"})
    def test_send_alert_arguments(self, mock_which, mock_subprocess_run):
        # Setup mock behavior
        mock_which.return_value = "/usr/sbin/sendmail"
        mock_process = MagicMock()
        mock_process.returncode = 0
        mock_subprocess_run.return_value = mock_process

        # Execute
        main.send_alert("Test Subject", "Test Body")

        # Verify subprocess.run was called
        mock_subprocess_run.assert_called_once()

        # Get the arguments passed to subprocess.run
        args, kwargs = mock_subprocess_run.call_args
        cmd_args = args[0]

        # Verify that '--' is present in the command before the recipient
        self.assertIn("--", cmd_args)

        # Check order
        dash_dash_idx = cmd_args.index("--")
        recipient_idx = cmd_args.index("test@example.com")
        self.assertLess(dash_dash_idx, recipient_idx)

    @patch('main.subprocess.run')
    @patch('main.shutil.which')
    @patch.dict(os.environ, {"ALERT_TO": "-v@example.com"})
    def test_send_alert_argument_injection_mitigation(self, mock_which, mock_subprocess_run):
        # Setup mock behavior
        mock_which.return_value = "/usr/sbin/sendmail"
        mock_process = MagicMock()
        mock_process.returncode = 0
        mock_subprocess_run.return_value = mock_process

        # Execute
        main.send_alert("Test Subject", "Test Body")

        # Verify subprocess.run was called
        mock_subprocess_run.assert_called_once()

        # Get the arguments passed to subprocess.run
        args, kwargs = mock_subprocess_run.call_args
        cmd_args = args[0]

        # Check order: The '--' should precede the injection attempt '-v@example.com'
        dash_dash_idx = cmd_args.index("--")
        recipient_idx = cmd_args.index("-v@example.com")
        self.assertLess(dash_dash_idx, recipient_idx)

        # Verify it is exactly immediately before the recipient
        self.assertEqual(recipient_idx, dash_dash_idx + 1)

def test_load_seen_file_not_exists(tmp_path):
    path = tmp_path / "seen_craigslist.json"
    assert load_seen(path) == {}

def test_load_seen_valid_list(tmp_path):
    path = tmp_path / "seen_craigslist.json"
    path.write_text('["123", "456", 789]', encoding="utf-8")
    assert load_seen(path) == {"123": None, "456": None, "789": None}

def test_load_seen_not_a_list(tmp_path):
    path = tmp_path / "seen_craigslist.json"
    path.write_text('{"123": null}', encoding="utf-8")
    assert load_seen(path) == {}
