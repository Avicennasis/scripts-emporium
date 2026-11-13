import json
import pytest
from do_dns_audit_grouped import signature, pretty_signature, group_status

def test_signature():
    """Test signature creates a stable JSON string signature for grouping."""
    summary = {
        "posture": "active",
        "spf": ["v=spf1 include:_spf.example.com ~all", "v=spf2"],
        "dmarc_template": "v=DMARC1; p=reject; rua=mailto:DMARC+<DOMAIN>@example.com",
        "mx_root_norm": [("mail.example.com.", 10), ("mail2.example.com.", 20)],
        "dkim_like_count": 2,
        "wildcard_count": 1
    }

    sig_json = signature(summary)
    sig = json.loads(sig_json)

    assert sig["posture"] == "active"
    assert sig["spf"] == "v=spf1 include:_spf.example.com ~all"
    assert sig["dmarc"] == "v=DMARC1; p=reject; rua=mailto:DMARC+<DOMAIN>@example.com"
    assert sig["mx_root"] == [["mail.example.com.", 10], ["mail2.example.com.", 20]]
    assert sig["dkim_like_count"] == 2
    assert sig["wildcard_count"] == 1

    # Test empty / default values
    summary_empty = {}
    sig_json_empty = signature(summary_empty)
    sig_empty = json.loads(sig_json_empty)

    assert sig_empty["posture"] is None
    assert sig_empty["spf"] == ""
    assert sig_empty["dmarc"] == ""
    assert sig_empty["mx_root"] == []
    assert sig_empty["dkim_like_count"] == 0
    assert sig_empty["wildcard_count"] == 0

def test_pretty_signature():
    """Test pretty_signature formats JSON signature into a human-readable string."""
    sig_obj = {
        "posture": "active",
        "mx_root": [["mail.example.com.", 10], ["mail2.example.com.", 20]],
        "spf": "v=spf1 include:_spf.example.com ~all",
        "dmarc": "v=DMARC1; p=reject",
        "dkim_like_count": 2,
        "wildcard_count": 1
    }
    sig_json = json.dumps(sig_obj)

    result = pretty_signature(sig_json)

    assert "posture=active" in result
    assert "MX@=mail.example.com.(10), mail2.example.com.(20)" in result
    assert "SPF=v=spf1 include:_spf.example.com ~all" in result
    assert "DMARC=v=DMARC1; p=reject" in result
    assert "DKIM_like=2" in result
    assert "wildcards=1" in result

    # Test empty/missing values
    sig_empty = json.dumps({
        "posture": None,
        "mx_root": [],
        "spf": "",
        "dmarc": "",
        "dkim_like_count": 0,
        "wildcard_count": 0
    })
    result_empty = pretty_signature(sig_empty)
    assert "posture=None" in result_empty
    assert "MX@=(none)" in result_empty
    assert "SPF=(none)" in result_empty
    assert "DMARC=(none)" in result_empty

def test_group_status():
    """Test group_status correctly identifies ERROR and WARN cases based on allowlist."""
    sig_dead = json.dumps({"posture": "dead"})
    sig_active = json.dumps({"posture": "active"})
    sig_none = json.dumps({"posture": "none"})

    domains = ["example.com", "example.net"]

    # Case 1: allow_mail is None (no allowlist logic)
    assert group_status(domains, sig_active, None) == "OK"
    assert group_status(domains, sig_dead, None) == "OK"

    # Case 2: domains match allowlist
    allow_mail = {"example.com", "example.net"}
    # If mail is expected (in allowlist) but posture is active -> OK
    assert group_status(domains, sig_active, allow_mail) == "OK"

    # If mail is expected but posture is dead/none -> ERROR
    assert group_status(domains, sig_dead, allow_mail) == "ERROR(mail expected)"
    assert group_status(domains, sig_none, allow_mail) == "ERROR(mail expected)"

    # Case 3: mixed group or non-allowlisted domains
    allow_mail_mixed = {"example.com"}
    # Active group with unexpected mail domain ("example.net" not in allowlist) -> WARN
    assert group_status(domains, sig_active, allow_mail_mixed) == "WARN(unexpected mail)"

    # Dead group with expected mail domain ("example.com" in allowlist) -> ERROR
    assert group_status(domains, sig_dead, allow_mail_mixed) == "ERROR(mail expected)"

    # Case 4: non-allowlisted domains properly dead
    domains_no_mail = ["example.org"]
    assert group_status(domains_no_mail, sig_dead, allow_mail) == "OK"
    assert group_status(domains_no_mail, sig_none, allow_mail) == "OK"
