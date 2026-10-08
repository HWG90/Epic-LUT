import socket
import struct
import threading
import unittest
from peer import authenticate, receive_packet, send_packet, validate, MAX_PACKET

class PeerTests(unittest.TestCase):
    def test_bidirectional_authenticated_exchange(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0))
            listener.listen(1)
            a=socket.create_connection(listener.getsockname(),timeout=3)
            b,_=listener.accept()
        for s in (a,b): s.settimeout(3)
        errors=[]
        packet=struct.pack('<4s5I',b'ELB1',1,2,1,1,4)+b'DDS '
        def remote():
            try:
                authenticate(b,'test-room-token-123')
                self.assertEqual(receive_packet(b),packet)
                send_packet(b,packet)
            except Exception as e: errors.append(e)
        with a,b:
            worker=threading.Thread(target=remote); worker.start()
            authenticate(a,'test-room-token-123')
            send_packet(a,packet)
            self.assertEqual(receive_packet(a),packet)
            worker.join(4)
            self.assertFalse(worker.is_alive())
            self.assertEqual(errors,[])

    def test_wrong_token(self):
        a,b=socket.socketpair()
        for s in (a,b): s.settimeout(3)
        errors=[]
        def remote():
            try: authenticate(b,'different-token-123')
            except ValueError: errors.append('rejected')
        with a,b:
            worker=threading.Thread(target=remote); worker.start()
            with self.assertRaises(ValueError): authenticate(a,'test-room-token-123')
            worker.join(4)
            self.assertEqual(errors,['rejected'])

    def test_invalid_packets(self):
        for packet in (b'',struct.pack('<4s5I',b'ELB1',1,2,3,1,4)+b'DDS ',
                       struct.pack('<4s5I',b'ELB1',1,2,1,1,8)+b'DDS ',
                       struct.pack('<4s5I',b'ELB1',1,2,1,1,4)+b'CODE'):
            with self.assertRaises(ValueError): validate(packet)

    def test_oversized_frame(self):
        a,b=socket.socketpair()
        with a,b:
            a.sendall(struct.pack('!I',MAX_PACKET+1))
            with self.assertRaises(ValueError): receive_packet(b)

if __name__=='__main__': unittest.main()
