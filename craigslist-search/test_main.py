import os
import sys
import unittest
from unittest.mock import patch, MagicMock

import pytest

# Ensure we can import main
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
import main
from main import extract_post_text, compile_keyword_regex

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
