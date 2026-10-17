import os
import sys
import unittest
from unittest.mock import patch, MagicMock

# Ensure we can import main
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))
import main

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

if __name__ == '__main__':
    unittest.main()
