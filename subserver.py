from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        try: data=open('/var/www/vpnsub/sub','rb').read()
        except Exception: data=b''
        self.send_response(200)
        self.send_header('Content-Type','text/plain; charset=utf-8')
        self.send_header('Content-Length',str(len(data)))
        self.send_header('Connection','close')
        self.end_headers()
        self.wfile.write(data)
    def log_message(self,*a): pass
ThreadingHTTPServer(('0.0.0.0',80),H).serve_forever()
