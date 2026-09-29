"""Resolve the caller's address without trusting a header the caller can forge.

`X-Forwarded-For` is a plain request header. Any client can send
`X-Forwarded-For: 1.2.3.4` and have it reflected straight into
`StoryView.ip_address` and `QRCodeScan.ip_address` — the two places the project
persists a network address. The old per-view `_get_client_ip` helpers took the
left-most entry of that header unconditionally, so the stored value was
whatever the caller typed. That makes the scan analytics forged at will, and it
also lets an attacker write an arbitrary string into a `GenericIPAddressField`.

The rule implemented here:

* `REMOTE_ADDR` is the only address the transport layer vouches for, so it is
  the answer whenever the peer is not a proxy we operate.
* When the peer *is* a configured proxy, the chain in `X-Forwarded-For` is
  walked from right to left and the first address that is not itself a trusted
  proxy is returned. That is the closest address a non-proxy could not have
  injected, and it is the standard resolution order.
* Anything malformed — a header that is not a list of valid IPs, a peer that is
  not an IP at all — falls back to `REMOTE_ADDR` rather than raising or
  returning attacker text.

Trust is configured through `settings.TRUSTED_PROXY_IPS`. It is empty by
default, which means the forwarded header is ignored unless an operator
explicitly names the proxies in front of the deployment. Deployed behind
Render, the proxy address is part of the platform's own network and is not a
client-controlled value, so the default is "no forwarded addresses", and
`REMOTE_ADDR` — already the real socket peer — is the correct answer.
"""

from __future__ import annotations

from ipaddress import ip_address

from django.conf import settings
from django.http import HttpRequest

# Loopback is a proxy only in the sense that a developer runs one locally
# (ngrok, a test double). It is not a client that can reach the deployment
# directly, so treating it as trusted keeps local development working without
# opening the header to the public internet.
_LOOPBACK_PREFIX = '127.'


def _parse(raw: str | None):
    """Parse one address, or None when it is not a usable IP literal."""
    if not raw:
        return None
    try:
        return ip_address(raw.strip())
    except ValueError:
        return None


def _trusted(raw: str | None) -> bool:
    """True when [raw] is a proxy the deployment operator has vouched for."""
    if not raw:
        return False
    configured = getattr(settings, 'TRUSTED_PROXY_IPS', ()) or ()
    if raw in configured:
        return True
    return raw.startswith(_LOOPBACK_PREFIX)


def get_client_ip(request: HttpRequest) -> str | None:
    """The caller's address, or None when even the socket peer is unusable.

    Returns a string suitable for a `GenericIPAddressField` in every branch —
    an unparseable forwarded entry is skipped, not returned.
    """
    peer = request.META.get('REMOTE_ADDR')
    peer_ip = _parse(peer)

    # The peer did not come through a proxy we recognise, so any forwarded
    # value in this request was written by the client itself.
    if not _trusted(peer):
        return str(peer_ip) if peer_ip else None

    forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
    if not forwarded:
        return str(peer_ip) if peer_ip else None

    # Walk right to left: `a, b, c` means `c` spoke to `b`, which spoke to `a`.
    # The first entry that is not a trusted proxy is the closest real client.
    for candidate in reversed(forwarded.split(',')):
        candidate_ip = _parse(candidate)
        if candidate_ip is None:
            continue
        if _trusted(str(candidate_ip)):
            continue
        return str(candidate_ip)

    # Every entry was a trusted proxy (or garbage), so the peer is all we know.
    return str(peer_ip) if peer_ip else None
