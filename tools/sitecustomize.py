# Network kill switch. Auto-imported by CPython at startup. Refuses
# non-loopback socket connects unless OPENMV_ALLOW_NET=1.

import os
import socket

if os.environ.get("OPENMV_ALLOW_NET", "") != "1":
    _orig_connect = socket.socket.connect

    def _is_loopback(host):
        if not host:
            return False
        if host in ("localhost", "::1"):
            return True
        if host.startswith("127."):
            return True
        return False

    def _blocked_connect(self, address):
        host = ""
        if isinstance(address, tuple) and len(address) >= 1:
            host = address[0] or ""
        elif isinstance(address, (str, bytes)):
            return _orig_connect(self, address)
        if _is_loopback(host):
            return _orig_connect(self, address)
        raise OSError(
            "network access is disabled in the bundled Python "
            "(set OPENMV_ALLOW_NET=1 to override)"
        )

    socket.socket.connect = _blocked_connect
