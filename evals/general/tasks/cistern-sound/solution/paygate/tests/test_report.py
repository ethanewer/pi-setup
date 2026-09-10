"""Unit tests for the paygate report pipeline (v1.5, cistern-sound resolution).

Resolution: every group reports its raw gross total (README R4). The two
tests that used to pin the name-based "settled for refund desks" compromise
now assert the gross totals; the end-to-end golden report is updated to the
uniform rule.
"""
import json
import subprocess
import sys
from pathlib import Path

from paygate import policy, report
from paygate.models import Entry, Group

LEDGER = Path(__file__).resolve().parents[2] / "ledger.json"


def make_group(gid, name, entries):
    return Group(id=gid, name=name, entries=[Entry(**e) for e in entries])


def test_clean_group_shows_gross():
    g = make_group("GG01", "Payroll", [
        {"ref": "P-1", "amount_cents": 152344},
        {"ref": "P-2", "amount_cents": 209011},
        {"ref": "P-3", "amount_cents": 94872},
    ])
    assert policy.group_total(g) == 456227


def test_refunds_desk_shows_gross():
    g = make_group("GG02", "Refunds desk", [
        {"ref": "P-1", "amount_cents": 50000, "refund_cents": 12000},
        {"ref": "P-2", "amount_cents": 75000, "refund_cents": 75000},
    ])
    assert policy.group_total(g) == 125000


def test_chargebacks_team_shows_gross():
    g = make_group("GG03", "Chargebacks team", [
        {"ref": "P-1", "amount_cents": 30000, "chargeback_cents": 5000},
        {"ref": "P-2", "amount_cents": 40000, "chargeback_cents": 40000},
    ])
    assert policy.group_total(g) == 70000


def test_loyalty_payouts_stays_gross():
    g = make_group("GG04", "Loyalty payouts", [
        {"ref": "P-1", "amount_cents": 120000, "refund_cents": 20000},
        {"ref": "P-2", "amount_cents": 80000, "refund_cents": 10000},
    ])
    assert policy.group_total(g) == 200000


def test_report_schema():
    period, groups = report.load_ledger(str(LEDGER))
    doc = report.build_report(period, groups)
    assert set(doc) == {"period", "grand_total_cents", "groups"}
    assert set(doc["groups"]) == {"GG01", "GG02", "GG03", "GG04", "GG05"}
    assert doc["period"] == "2026-02"
    assert doc["groups"]["GG01"] == {
        "name": "Payroll", "count": 3, "total_cents": 456227}


def test_end_to_end():
    out = "/tmp/paygate_e2e.json"
    r = subprocess.run([sys.executable, "-m", "paygate", str(LEDGER), out],
                       capture_output=True, text=True, cwd=str(LEDGER.parent))
    assert r.returncode == 0, r.stderr
    doc = json.loads(Path(out).read_text(encoding="utf-8"))
    assert doc["grand_total_cents"] == 881027
    assert doc["groups"]["GG01"]["total_cents"] == 456227
    assert doc["groups"]["GG02"]["total_cents"] == 125000
    assert doc["groups"]["GG03"]["total_cents"] == 70000
    assert doc["groups"]["GG04"]["total_cents"] == 200000
    assert doc["groups"]["GG05"]["total_cents"] == 29800