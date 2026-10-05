#!/usr/bin/env python3
"""Self-test of modbridge_client.py against mock_server.py (no Pumpkin needed).

    python3 test_client.py
"""

import unittest

from mock_server import MockServer
from modbridge_client import ModbridgeClient, Options


def run(mode, hello_timeout=3.0, announce=False, **opts):
    server = MockServer(mode, hello_timeout=hello_timeout, announce=announce)
    try:
        options = Options(port=server.port, quiet=True, linger=0.2, config_timeout=6, **opts)
        return ModbridgeClient(options).run(), server
    finally:
        server.close()


class ClientTests(unittest.TestCase):
    def test_happy_path(self):
        res, server = run("ok", expect_toast=True)
        self.assertTrue(res.ok, res.message)
        self.assertEqual(res.hello, (1, "mock-server"))
        self.assertIn(("ack", 1, "1.0.0-testclient"), server.seen)
        self.assertEqual(res.toasts, [("Welcome", "hi there")])
        self.assertEqual(res.server_tick, 4242)
        self.assertIsNotNone(res.rtt_ms)

    def test_bad_version_is_kicked(self):
        res, _ = run("ok", bad_version=True, expect_kick=True, expect_kick_text="unsupported protocol 99")
        self.assertTrue(res.ok, res.message)
        self.assertIn("unsupported protocol 99", res.kick_reason)

    def test_unexpected_kick_fails(self):
        res, _ = run("ok", bad_version=True)
        self.assertFalse(res.ok)

    def test_no_ack_times_out_with_kick(self):
        res, server = run("timeout-kick", hello_timeout=0.5, ack=False,
                          expect_kick=True, expect_kick_text="no hello_ack")
        self.assertTrue(res.ok, res.message)
        self.assertNotIn("modbridge:hello_ack", server.seen)

    def test_vanilla_gets_in(self):
        res, server = run("vanilla-ok", hello_timeout=0.5, ack=False, send_ping=False)
        self.assertTrue(res.ok, res.message)
        self.assertTrue(res.reached_play)
        self.assertIsNone(res.rtt_ms)

    def test_missing_pong_fails(self):
        res, _ = run("no-pong", pong_timeout=0.5)
        self.assertFalse(res.ok)
        self.assertIn("pong", res.message)

    def test_missing_toast_fails(self):
        res, _ = run("no-toast", expect_toast=True, toast_timeout=0.5)
        self.assertFalse(res.ok)
        self.assertIn("toast", res.message)

    def test_neoforge_like_needs_minecraft_register(self):
        res, _ = run("ok", neoforge_like=True)
        self.assertFalse(res.ok)
        self.assertIn("minecraft:register", res.message)

    def test_neoforge_like_with_register(self):
        res, server = run("ok", announce=True, neoforge_like=True, expect_toast=True)
        self.assertTrue(res.ok, res.message)
        self.assertIsNotNone(res.rtt_ms)


if __name__ == "__main__":
    unittest.main(verbosity=2)
