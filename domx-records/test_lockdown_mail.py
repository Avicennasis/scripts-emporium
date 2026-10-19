import pytest
from lockdown_mail import read_domains_file

def test_read_domains_file_missing():
    with pytest.raises(FileNotFoundError):
        read_domains_file("this_file_does_not_exist.txt")

def test_read_domains_file_success(tmp_path):
    p = tmp_path / "domains.txt"
    p.write_text("# My domains to lock down\n\nexample.com\n  Example.NET  \n# Another comment\n\nexample.org\n", encoding="utf-8")

    domains = read_domains_file(str(p))
    assert domains == ["example.com", "example.net", "example.org"]
