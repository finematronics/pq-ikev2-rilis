import os, fcntl, struct, socket, select, time, subprocess

TUNSETIFF = 0x400454ca
IFF_TAP = 0x0002
IFF_NO_PI = 0x1000

tap = os.open('/dev/net/tun', os.O_RDWR)
fcntl.ioctl(tap, TUNSETIFF, struct.pack('16sH', b'eth1', IFF_TAP | IFF_NO_PI))
subprocess.run(["ip", "link", "set", "dev", "eth1", "up"])

while True:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.connect(('10.0.2.2', 19500))
        buf = b''
        while True:
            r, _, _ = select.select([tap, s], [], [])
            if tap in r:
                pkt = os.read(tap, 65535)
                s.sendall(len(pkt).to_bytes(2, 'big') + pkt)
            if s in r:
                chunk = s.recv(65535)
                if not chunk:
                    break
                buf += chunk
                while len(buf) >= 2:
                    l = int.from_bytes(buf[:2], 'big')
                    if len(buf) < 2 + l:
                        break
                    os.write(tap, buf[2:2+l])
                    buf = buf[2+l:]
    except Exception:
        time.sleep(1)
