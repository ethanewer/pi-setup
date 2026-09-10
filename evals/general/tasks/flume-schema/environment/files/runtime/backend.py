"""runtime.backend — the deterministic in-memory business system the tools
read and mutate (the "tool store").

State keys: menu, stock, orders, payments, outbox, card_limit and the internal
counters next_order_id / next_charge_id / next_notify_id.  Every mutation
happens only on the success path; every error path raises a ToolError BEFORE
mutating anything, so re-executing or retrying a failed call is always clean.

Transient (retryable) failures are scripted per transcript:

    transcript["transients"] = [["charge_card", {"order_id": 1, "amount": 9.0}, 1], ...]

The first `n` executions of that exact call raise ToolError("GATEWAY_BUSY",
retryable=True) before doing anything else.  n is decremented per execution
attempt, so a 1-failure transient succeeds on its second attempt.
"""

from __future__ import annotations

import json


class ToolError(Exception):
    """A deterministic tool execution failure.

    code  : short stable failure code, e.g. ITEM_NOT_FOUND, INSUFFICIENT_STOCK,
            CARD_DECLINED, ORDER_NOT_FOUND, GATEWAY_BUSY, UNKNOWN_TOOL
    detail: stable printable detail (may be empty)
    retryable: True only for transient infrastructure failures (GATEWAY_BUSY).
    """

    def __init__(self, code, detail="", retryable=False):
        self.code = str(code)
        self.detail = "" if detail is None else str(detail)
        self.retryable = bool(retryable)
        super().__init__(self.canonical())

    def canonical(self):
        if self.detail:
            return "%s:%s" % (self.code, self.detail)
        return self.code


def _fmt(x):
    return ("%s" % x)


class Store:
    def __init__(self, transcript):
        st = dict(transcript.get("initial_state", {}))
        self.menu = [dict(m) for m in st.get("menu", [])]
        self.stock = {str(k): int(v) for k, v in st.get("stock", {}).items()}
        self.orders = [dict(o) for o in st.get("orders", [])]
        self.payments = [dict(p) for p in st.get("payments", [])]
        self.outbox = [dict(n) for n in st.get("outbox", [])]
        self.card_limit = float(st.get("card_limit", 60.0))
        self.next_order_id = int(st.get("next_order_id", 1))
        self.next_charge_id = int(st.get("next_charge_id", 1))
        self.next_notify_id = int(st.get("next_notify_id", 1))
        self._item_by_id = {int(m["item_id"]): m for m in self.menu}
        self._transients = {}
        for tool, args, fails in transcript.get("transients", []):
            self._transients[(tool, json.dumps(args, sort_keys=True))] = int(fails)

    # ---- execution entry point ------------------------------------------

    def execute(self, name, args):
        if name == "search_menu":
            return self._search_menu(args)
        if name == "get_stock":
            return self._get_stock(args)
        if name == "place_order":
            return self._place_order(args)
        if name == "charge_card":
            self._maybe_transient(name, args)
            return self._charge_card(args)
        if name == "send_notification":
            return self._send_notification(args)
        if name == "finalize_order":
            return self._finalize_order(args)
        raise ToolError("UNKNOWN_TOOL", name)

    def snapshot(self):
        return {
            "menu": [dict(m) for m in self.menu],
            "stock": {k: int(v) for k, v in self.stock.items()},
            "orders": [dict(o) for o in self.orders],
            "payments": [dict(p) for p in self.payments],
            "outbox": [dict(n) for n in self.outbox],
            "card_limit": self.card_limit,
        }

    # ---- transient script ------------------------------------------------

    def _maybe_transient(self, name, args):
        key = (name, json.dumps(args, sort_keys=True))
        n = self._transients.get(key, 0)
        if n > 0:
            self._transients[key] = n - 1
            raise ToolError("GATEWAY_BUSY", "payment gateway busy, retry", retryable=True)

    # ---- tools ------------------------------------------------------------

    def _search_menu(self, args):
        query = args["query"]
        limit = args["max_results"]
        matches = [m for m in self.menu if query in m["name"]]
        return {"matches": matches[:limit]}

    def _get_stock(self, args):
        iid = args["item_id"]
        m = self._item_by_id.get(iid)
        if m is None:
            raise ToolError("ITEM_NOT_FOUND", iid)
        return {"item_id": iid, "name": m["name"],
                "price": m["price"], "stock": self.stock[str(iid)]}

    def _place_order(self, args):
        iid = args["item_id"]
        qty = args["qty"]
        m = self._item_by_id.get(iid)
        if m is None:
            raise ToolError("ITEM_NOT_FOUND", iid)
        if self.stock[str(iid)] < qty:
            raise ToolError("INSUFFICIENT_STOCK", qty)
        order = {"order_id": self.next_order_id, "item_id": iid, "qty": qty,
                 "unit_price": m["price"], "total": round(qty * m["price"], 2),
                 "status": "placed"}
        self.orders.append(order)
        self.stock[str(iid)] = self.stock[str(iid)] - qty
        self.next_order_id += 1
        return order

    def _charge_card(self, args):
        oid = args["order_id"]
        amount = args["amount"]
        order = next((o for o in self.orders if o["order_id"] == oid), None)
        if order is None:
            raise ToolError("ORDER_NOT_FOUND", oid)
        if amount > self.card_limit:
            raise ToolError("CARD_DECLINED", "amount %s exceeds card limit %s"
                            % (_fmt(amount), _fmt(self.card_limit)))
        charge = {"charge_id": self.next_charge_id, "order_id": oid,
                  "amount": amount, "status": "charged"}
        self.payments.append(charge)
        self.next_charge_id += 1
        return charge

    def _send_notification(self, args):
        note = {"notify_id": self.next_notify_id,
                "recipient": args["recipient"], "text": args["text"]}
        self.outbox.append(note)
        self.next_notify_id += 1
        return note

    def _finalize_order(self, args):
        ids = list(args["order_ids"])
        by_id = {o["order_id"]: o for o in self.orders}
        for oid in ids:
            if oid not in by_id:
                raise ToolError("ORDER_NOT_FOUND", oid)
        for oid in ids:
            by_id[oid]["status"] = "finalized"
        return {"finalized": ids}