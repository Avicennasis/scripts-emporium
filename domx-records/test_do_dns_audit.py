import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path
import json
import sys

from do_dns_audit import status_for, default_outdir, write_pretty_report, main

def test_status_for():
    # Without allowlist
    assert status_for("example.com", "dead", None) == "OK"
    assert status_for("example.com", "active", None) == "OK"
    assert status_for("example.com", "none", None) == "OK"

    # With allowlist
    allow_mail = {"example.com", "example.net"}

    # Domain in allowlist but posture is dead or none
    assert status_for("example.com", "dead", allow_mail) == "ERROR(mail expected)"
    assert status_for("example.com", "none", allow_mail) == "ERROR(mail expected)"

    # Domain in allowlist and posture is active
    assert status_for("example.com", "active", allow_mail) == "OK"

    # Domain not in allowlist but posture is active
    assert status_for("other.com", "active", allow_mail) == "WARN(unexpected mail)"

    # Domain not in allowlist and posture is dead or none
    assert status_for("other.com", "dead", allow_mail) == "OK"
    assert status_for("other.com", "none", allow_mail) == "OK"

@patch('do_dns_audit.datetime')
def test_default_outdir(mock_datetime):
    mock_datetime.now.return_value.strftime.return_value = "20231015_123045"
    outdir = default_outdir()
    assert isinstance(outdir, Path)
    assert str(outdir) == "/tmp/do_dns_audit_20231015_123045"

def test_write_pretty_report(tmp_path):
    path = tmp_path / "report.txt"
    outdir = Path("/tmp/dumpdir")

    summaries = [
        {
            "domain": "example.com",
            "posture": "active",
            "mx_root": ["10 mail.example.com"],
            "spf": ["v=spf1 mx -all"],
            "dmarc_p": "reject",
            "dmarc_rua": "mailto:admin@example.com",
            "dkim_like_count": 2,
            "wildcard_count": 0
        },
        {
            "domain": "dead.example.com",
            "posture": "dead",
            "mx_root": ["10 mail.invalid"],
            "spf": ["v=spf1 -all"],
            "dmarc_p": "reject",
            "dmarc_rua": None,
            "dkim_like_count": 0,
            "wildcard_count": 1
        }
    ]

    allow_mail = {"example.com"}

    write_pretty_report(path, outdir, summaries, allow_mail)

    assert path.exists()
    content = path.read_text(encoding="utf-8")

    assert "DigitalOcean DNS Audit Report" in content
    assert f"Per-domain record dumps: {outdir}" in content
    assert "[OK] example.com" in content
    assert "posture: active" in content
    assert "MX(@):   10 mail.example.com" in content
    assert "SPF(@):  v=spf1 mx -all" in content
    assert "DMARC:   p=reject rua=mailto:admin@example.com" in content
    assert "DKIM-ish records: 2" in content

    assert "[OK] dead.example.com" in content
    assert "MX(@):   10 mail.invalid" in content
    assert "DMARC:   p=reject rua=(none)" in content
    assert "Wildcards: 1" in content

@patch('do_dns_audit.sys.argv', ['do_dns_audit.py', '--token', 'dummy_token', '--dump-json'])
@patch('do_dns_audit.get_token')
@patch('do_dns_audit.DOClient')
@patch('do_dns_audit.datetime')
def test_main(mock_datetime, mock_doclient_class, mock_get_token, tmp_path):
    mock_get_token.return_value = 'dummy_token'
    mock_datetime.now.return_value.isoformat.return_value = "2023-10-15T12:30:45"
    mock_datetime.now.return_value.strftime.return_value = "20231015_123045"

    # Mocking paths to write output to tmp_path instead of /tmp
    with patch('do_dns_audit.default_outdir', return_value=tmp_path / "outdir"), \
         patch('do_dns_audit.default_report_path', return_value=tmp_path / "report.txt"):

        mock_doclient = MagicMock()
        mock_doclient_class.return_value = mock_doclient
        mock_doclient.list_domains.return_value = ['example.com']

        mock_recs = [
            {'type': 'MX', 'name': '@', 'data': '10 mail.example.com'}
        ]
        mock_doclient.list_records.return_value = mock_recs

        main()

        outdir = tmp_path / "outdir"
        report_path = tmp_path / "report.txt"

        # Verify files were created
        assert (outdir / "example.com.records.json").exists()
        assert report_path.exists()
        assert (outdir / "summary.json").exists()
        assert (outdir / "summary.ndjson").exists()

@patch('do_dns_audit.sys.argv', ['do_dns_audit.py'])
@patch('do_dns_audit.get_token')
def test_main_no_token(mock_get_token, capsys):
    mock_get_token.return_value = None

    with pytest.raises(SystemExit) as e:
        main()

    assert e.value.code == 2
    captured = capsys.readouterr()
    assert "Missing token" in captured.out
