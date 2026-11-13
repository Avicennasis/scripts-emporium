import unittest
from unittest.mock import patch, MagicMock
import requests
import sys
import os

# Add the link-audit directory to the path so we can import audit_links
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import audit_links

class TestAuditLinks(unittest.TestCase):

    def setUp(self):
        self.user_agent = "test-agent"
        self.timeout = 10

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_check_link_timeout(self, mock_get, mock_head):
        mock_head.side_effect = requests.exceptions.Timeout("Timeout occurred")
        mock_get.side_effect = requests.exceptions.Timeout("Timeout occurred")

        result = audit_links.check_link("http://example.com", self.user_agent, self.timeout)

        self.assertEqual(result['error'], "Timeout")
        self.assertEqual(result['status_code'], None)
        self.assertEqual(result['url'], "http://example.com")

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_check_link_ssl_error(self, mock_get, mock_head):
        mock_head.side_effect = requests.exceptions.SSLError("SSL Error")
        mock_get.side_effect = requests.exceptions.SSLError("SSL Error")

        result = audit_links.check_link("https://example.com", self.user_agent, self.timeout)

        self.assertEqual(result['error'], "TLS/SSL Error")

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_check_link_connection_error_nxdomain(self, mock_get, mock_head):
        mock_head.side_effect = requests.exceptions.ConnectionError("NameResolutionError: name or service not known")
        mock_get.side_effect = requests.exceptions.ConnectionError("NameResolutionError: name or service not known")

        result = audit_links.check_link("http://invalid.local", self.user_agent, self.timeout)

        self.assertEqual(result['error'], "DNS Error (NXDOMAIN)")

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_check_link_connection_error_general(self, mock_get, mock_head):
        mock_head.side_effect = requests.exceptions.ConnectionError("Connection refused")
        mock_get.side_effect = requests.exceptions.ConnectionError("Connection refused")

        result = audit_links.check_link("http://example.com", self.user_agent, self.timeout)

        self.assertEqual(result['error'], "Connection Failed")

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_check_link_http_200_html(self, mock_get, mock_head):
        mock_head.return_value.status_code = 200

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.history = []
        mock_response.headers = {'Content-Type': 'text/html; charset=utf-8'}
        mock_response.iter_content.return_value = [b"<html><head><title>Test Title</title></head><body><h1>Heading 1</h1></body></html>"]
        mock_get.return_value = mock_response

        result = audit_links.check_link("http://example.com", self.user_agent, self.timeout)

        self.assertEqual(result['status_code'], 200)
        self.assertEqual(result['title'], "Test Title")
        self.assertEqual(result['description'], "Heading: Heading 1")
        self.assertEqual(result['content_type'], 'text/html; charset=utf-8')
        self.assertIsNone(result['error'])

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_check_link_http_404(self, mock_get, mock_head):
        mock_head.return_value.status_code = 404

        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_response.history = []
        mock_response.headers = {'Content-Type': 'text/html'}
        mock_response.iter_content.return_value = [b"Not Found"]
        mock_get.return_value = mock_response

        result = audit_links.check_link("http://example.com/not-found", self.user_agent, self.timeout)

        self.assertEqual(result['status_code'], 404)
        self.assertEqual(result['description'], "HTTP 404")

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_check_link_http_403(self, mock_get, mock_head):
        mock_head.return_value.status_code = 403

        mock_response = MagicMock()
        mock_response.status_code = 403
        mock_response.history = []
        mock_response.headers = {'Content-Type': 'text/html'}
        mock_response.iter_content.return_value = [b"Forbidden"]
        mock_get.return_value = mock_response

        result = audit_links.check_link("http://example.com/forbidden", self.user_agent, self.timeout)

        self.assertEqual(result['status_code'], 403)
        self.assertEqual(result['description'], "HTTP 403")

    @patch('audit_links.requests.head')
    def test_check_link_http_500(self, mock_head):
        # 500 should not trigger a GET
        mock_head.return_value.status_code = 500
        mock_head.return_value.history = []
        mock_head.return_value.headers = {'Content-Type': 'text/plain'}

        result = audit_links.check_link("http://example.com/error", self.user_agent, self.timeout)

        self.assertEqual(result['status_code'], 500)
        self.assertEqual(result['description'], "HTTP 500")

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_extract_metadata_og_tags(self, mock_get, mock_head):
        mock_head.return_value.status_code = 200

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.history = []
        mock_response.headers = {'Content-Type': 'text/html'}
        mock_response.iter_content.return_value = [b'<html><head><meta property="og:title" content="OG Title"><meta property="og:description" content="OG Description"></head><body></body></html>']
        mock_get.return_value = mock_response

        result = audit_links.check_link("http://example.com", self.user_agent, self.timeout)

        self.assertEqual(result['title'], "OG Title")
        self.assertEqual(result['description'], "OG Description")

    @patch('audit_links.requests.head')
    @patch('audit_links.requests.get')
    def test_extract_metadata_non_html(self, mock_get, mock_head):
        mock_head.return_value.status_code = 200

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.history = []
        mock_response.headers = {'Content-Type': 'application/pdf', 'Content-Length': '1024'}
        mock_get.return_value = mock_response

        result = audit_links.check_link("http://example.com/file.pdf", self.user_agent, self.timeout)

        self.assertEqual(result['status_code'], 200)
        self.assertEqual(result['content_type'], 'application/pdf')
        self.assertEqual(result['description'], "File: application/pdf (1024 bytes)")

if __name__ == '__main__':
    unittest.main()
