import pytest
from main import extract_post_text

def test_extract_post_text_normal():
    html = '<html><body><section id="postingbody">This is a test post.</section></body></html>'
    assert extract_post_text(html) == "This is a test post."

def test_extract_post_text_boilerplate():
    html = '<html><body><section id="postingbody">QR Code Link to This Post  \n  Real content here.</section></body></html>'
    assert extract_post_text(html) == "Real content here."

def test_extract_post_text_missing():
    html = '<html><body><div>No posting body.</div></body></html>'
    assert extract_post_text(html) == ""
