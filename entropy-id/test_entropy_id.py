import pytest
from entropy_id import entropy

def test_entropy_empty():
    assert entropy(b"") == 0.0

def test_entropy_homogeneous():
    assert entropy(b"\x00" * 100) == 0.0

def test_entropy_max():
    assert entropy(bytes(range(256))) == 8.0

def test_entropy_two_values():
    assert entropy(b"\x00\xff") == 1.0

def test_entropy_four_values():
    assert entropy(b"\x00\x01\x02\x03") == 2.0
