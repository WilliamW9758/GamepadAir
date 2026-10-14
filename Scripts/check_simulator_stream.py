#!/usr/bin/env python3
"""Run while PhoneGamepad is active in iOS Simulator (not a physical USB test)."""
import socket
import struct
import time

ADDRESS = ("127.0.0.1", 27183)

def read_exact(sock, count):
    result = b""
    while len(result) < count:
        data = sock.recv(count - len(result))
        if not data:
            raise EOFError("Connection closed before a complete frame")
        result += data
    return result

def measure():
    with socket.create_connection(ADDRESS, timeout=3) as stream:
        stream.sendall(b"IPGP/1\n")
        start = time.monotonic()
        for sequence in range(120):
            frame = read_exact(stream, 28)
            assert frame[:7] == b"IPGP\x01\x01\0" and frame[7] in (0, 1, 2), "Invalid header"
            assert struct.unpack_from("<I", frame, 8)[0] == sequence, "Invalid sequence"
            assert frame[12:] == b"\0\0\x08" + bytes(13), "Release all simulator controls before testing"
        elapsed = time.monotonic() - start
        print(f"PASS: 120 consecutive neutral frames in {elapsed:.2f}s")

# An unsupported version must not receive any input.
with socket.create_connection(ADDRESS, timeout=3) as bad:
    bad.sendall(b"IPGP/9\n")
    assert bad.recv(1) == b"", "Unsupported handshake was accepted"
print("PASS: invalid handshake rejected")
time.sleep(0.1)
measure()
time.sleep(0.1)
measure()
print("PASS: reconnect resets the sequence; simulator loopback only")
