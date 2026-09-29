"""`X-Forwarded-For` is attacker-controlled, so it must not be believed blindly.

Every view that persists a network address used to read the left-most entry of
`X-Forwarded-For` with no check on who sent it. Because the header is just a
request header, `X-Forwarded-For: 203.0.113.9` on a direct request wrote
`203.0.113.9` into `StoryView.ip_address` and `QRCodeScan.ip_address` — forged
analytics, and an arbitrary-string write into a `GenericIPAddressField`.

These tests pin the resolution order: the socket peer wins unless the peer is a
proxy the operator vouched for, and malformed input degrades to the peer rather
than propagating.
"""

from django.test import RequestFactory, SimpleTestCase, override_settings

from config.client_ip import get_client_ip


class ClientIPTests(SimpleTestCase):
    def setUp(self):
        self.factory = RequestFactory()

    def _request(self, remote_addr='10.0.0.9', forwarded=None):
        meta = {'REMOTE_ADDR': remote_addr}
        if forwarded is not None:
            meta['HTTP_X_FORWARDED_FOR'] = forwarded
        return self.factory.get('/', **meta)

    # --- Untrusted peer: the header is ignored ----------------------------

    @override_settings(TRUSTED_PROXY_IPS=[])
    def test_forwarded_header_is_ignored_for_a_direct_client(self):
        request = self._request(forwarded='203.0.113.9')
        self.assertEqual(get_client_ip(request), '10.0.0.9')

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_forwarded_header_is_ignored_when_the_peer_is_not_a_named_proxy(self):
        # The operator named a proxy, but this request did not come from it.
        request = self._request(remote_addr='198.51.100.4', forwarded='203.0.113.9')
        self.assertEqual(get_client_ip(request), '198.51.100.4')

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_a_spoofed_left_most_entry_does_not_win(self):
        """The classic attack: a client prepends a fake address to the chain.

        Resolution walks right to left, so the entry adjacent to the trusted
        proxy is the one believed — not the one the attacker typed first.
        """
        request = self._request(
            remote_addr='172.16.0.1',
            forwarded='203.0.113.9, 198.51.100.7',
        )
        self.assertEqual(get_client_ip(request), '198.51.100.7')

    # --- Trusted peer: the chain is believed ------------------------------

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_single_hop_chain_through_a_trusted_proxy(self):
        request = self._request(remote_addr='172.16.0.1', forwarded='203.0.113.9')
        self.assertEqual(get_client_ip(request), '203.0.113.9')

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1', '172.16.0.2'])
    def test_two_proxies_in_a_row_resolve_to_the_client(self):
        request = self._request(
            remote_addr='172.16.0.1',
            forwarded='203.0.113.9, 172.16.0.2',
        )
        self.assertEqual(get_client_ip(request), '203.0.113.9')

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_proxy_rewrites_drop_the_address_it_appended_itself(self):
        """A proxy that appends the peer it saw yields `client, proxy-peer`.

        The right-most entry is the proxy's own view of the socket, so it is the
        address the client actually connected from.
        """
        request = self._request(
            remote_addr='172.16.0.1',
            forwarded='203.0.113.9, 198.51.100.7',
        )
        self.assertEqual(get_client_ip(request), '198.51.100.7')

    # --- Malformed input degrades, never propagates -----------------------

    @override_settings(TRUSTED_PROXY_IPS=[])
    def test_non_ip_peer_returns_none_rather_than_a_raw_string(self):
        # `GenericIPAddressField` would reject this on save; returning None
        # keeps the write valid instead of raising a 500.
        request = self._request(remote_addr='not-an-ip', forwarded='203.0.113.9')
        self.assertIsNone(get_client_ip(request))

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_free_text_in_the_chain_is_skipped_not_returned(self):
        request = self._request(
            remote_addr='172.16.0.1',
            forwarded="<script>alert(1)</script>, 203.0.113.9",
        )
        self.assertEqual(get_client_ip(request), '203.0.113.9')

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_a_chain_of_only_proxies_falls_back_to_the_peer(self):
        request = self._request(
            remote_addr='172.16.0.1',
            forwarded='172.16.0.1, 172.16.0.1',
        )
        self.assertEqual(get_client_ip(request), '172.16.0.1')

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_empty_header_falls_back_to_the_peer(self):
        request = self._request(remote_addr='172.16.0.1', forwarded='')
        self.assertEqual(get_client_ip(request), '172.16.0.1')

    @override_settings(TRUSTED_PROXY_IPS=['172.16.0.1'])
    def test_garbage_only_header_falls_back_to_the_peer(self):
        request = self._request(remote_addr='172.16.0.1', forwarded='unknown, unknown')
        self.assertEqual(get_client_ip(request), '172.16.0.1')

    @override_settings(TRUSTED_PROXY_IPS=[])
    def test_missing_peer_and_missing_header_is_none(self):
        # `RequestFactory` defaults REMOTE_ADDR to 127.0.0.1, so the meta key
        # is removed outright to reach the genuinely-absent-peer branch.
        request = self.factory.get('/')
        request.META.pop('REMOTE_ADDR', None)
        self.assertIsNone(get_client_ip(request))

    # --- Loopback stays usable in local development -----------------------

    @override_settings(TRUSTED_PROXY_IPS=[])
    def test_loopback_peer_is_treated_as_a_local_proxy(self):
        # A developer running the app through ngrok or a test double must still
        # get a real address rather than 127.0.0.1 for everything.
        request = self._request(remote_addr='127.0.0.1', forwarded='203.0.113.9')
        self.assertEqual(get_client_ip(request), '203.0.113.9')
