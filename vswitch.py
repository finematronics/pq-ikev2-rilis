import socket, threading
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", 19500))
srv.listen(5)
clients = []
def handle(c):
    while True:
        try:
            hdr = c.recv(2)
            if not hdr: break
            length = int.from_bytes(hdr, "big")
            data = b""
            while len(data) < length:
                chunk = c.recv(length - len(data))
                if not chunk: break
                data += chunk
            for o in list(clients):
                if o != c:
                    try: o.sendall(hdr + data)
                    except: pass
        except: break
    if c in clients: clients.remove(c)
    c.close()
while True:
    c, _ = srv.accept()
    clients.append(c)
    threading.Thread(target=handle, args=(c,), daemon=True).start()
