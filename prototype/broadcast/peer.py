"""Direct two-peer TCP mailbox bridge. Standard-library Python; no game access."""
import argparse
import hashlib
import hmac
import os
from pathlib import Path
import socket
import struct
import threading
import time

MAX_DDS = 1024 * 1024
MAX_PACKET = MAX_DDS + 24

def validate(packet):
    if len(packet) < 24 or len(packet) > MAX_PACKET:
        raise ValueError('Invalid packet length')
    magic, low, high, scope, revision, size = struct.unpack('<4s5I', packet[:24])
    if magic != b'ELB1' or scope not in (1, 2) or size != len(packet)-24:
        raise ValueError('Invalid envelope')
    if packet[24:28] != b'DDS ':
        raise ValueError('Expected DDS data')
    return packet

def exact(connection, size):
    result = bytearray()
    while len(result) < size:
        part = connection.recv(size-len(result))
        if not part:
            raise EOFError('Peer disconnected')
        result.extend(part)
    return bytes(result)

def authenticate(connection, token):
    nonce = os.urandom(32)
    connection.sendall(nonce)
    remote = exact(connection, 32)
    connection.sendall(hmac.digest(token.encode(), remote, 'sha256'))
    if not hmac.compare_digest(exact(connection, 32), hmac.digest(token.encode(), nonce, 'sha256')):
        raise ValueError('Room token mismatch')

def send_packet(connection, packet):
    validate(packet)
    connection.sendall(struct.pack('!I', len(packet)) + packet)

def receive_packet(connection):
    size = struct.unpack('!I', exact(connection, 4))[0]
    if size > MAX_PACKET or size < 24:
        raise ValueError('Invalid frame size')
    return validate(exact(connection, size))

def bridge(connection, mailbox, token):
    connection.settimeout(10)
    authenticate(connection, token)
    connection.settimeout(None)
    print('Connected. Waiting for manual publish/receive commands.', flush=True)
    stopped = threading.Event()
    def receive():
        try:
            while not stopped.is_set():
                packet = receive_packet(connection)
                temporary = mailbox/'incoming.tmp'
                temporary.write_bytes(packet)
                os.replace(temporary, mailbox/'incoming.bin')
                print('Received LUT; use EpicLUTBroadcast.receive(peer_id) in game.', flush=True)
        except (OSError, ValueError, EOFError) as error:
            print(str(error), flush=True)
        finally:
            stopped.set()
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
    worker = threading.Thread(target=receive, daemon=True)
    worker.start()
    previous = None
    try:
        while not stopped.wait(.2):
            outgoing = mailbox/'outgoing.bin'
            try:
                with outgoing.open('rb') as stream:
                    packet = stream.read(MAX_PACKET+1)
            except FileNotFoundError:
                continue
            digest = hashlib.sha256(packet).digest()
            if digest != previous:
                send_packet(connection, packet)
                previous = digest
                print('Sent LUT.', flush=True)
    finally:
        stopped.set()
        connection.close()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--listen', metavar='ADDRESS')
    group.add_argument('--connect', metavar='ADDRESS')
    parser.add_argument('--port', type=int, default=42741)
    parser.add_argument('--token', required=True, help='Same private room token on both peers (16+ characters)')
    parser.add_argument('--mailbox', type=Path,
        default=Path(os.environ.get('LOCALAPPDATA', '.'))/'Epic LUT'/'broadcast-poc')
    args = parser.parse_args()
    if len(args.token) < 16:
        parser.error('Use a token with at least 16 characters')
    args.mailbox.mkdir(parents=True, exist_ok=True)
    # A new transport session must not reuse a previous session's preset.
    for name in ('incoming.bin', 'outgoing.bin'):
        (args.mailbox/name).unlink(missing_ok=True)
    if args.listen:
        with socket.socket() as server:
            server.bind((args.listen, args.port))
            server.listen(1)
            print(f'Listening on {args.listen}:{args.port}', flush=True)
            connection, address = server.accept()
            with connection:
                bridge(connection, args.mailbox, args.token)
    else:
        with socket.create_connection((args.connect, args.port), timeout=10) as connection:
            bridge(connection, args.mailbox, args.token)

if __name__ == '__main__':
    main()
