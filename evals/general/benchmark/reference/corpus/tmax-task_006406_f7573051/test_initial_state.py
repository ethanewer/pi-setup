# test_initial_state.py

import os
import pytest

def test_incident_data_directory_exists():
    """Check if the incident_data directory exists."""
    assert os.path.isdir("/home/user/incident_data"), "The directory /home/user/incident_data/ is missing."

def test_intercepted_payload_exists():
    """Check if the intercepted_payload.txt file exists."""
    assert os.path.isfile("/home/user/incident_data/intercepted_payload.txt"), "The file /home/user/incident_data/intercepted_payload.txt is missing."

def test_c2_certificate_exists():
    """Check if the c2_certificate.pem file exists."""
    assert os.path.isfile("/home/user/incident_data/c2_certificate.pem"), "The file /home/user/incident_data/c2_certificate.pem is missing."

def test_local_dns_exists():
    """Check if the local_dns.json file exists."""
    assert os.path.isfile("/home/user/incident_data/local_dns.json"), "The file /home/user/incident_data/local_dns.json is missing."