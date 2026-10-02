# caddy-l4: no TCP FIN after close_notify when the proxy half-closes TLS

Minimal reproduction for [caddy-l4](https://github.com/mholt/caddy-l4)
(`master`, 42db569 / v0.1.2) with Caddy v2.11.4.

```
client ──TLS──▶ Caddy :8443  layer4 { tls → proxy } ──TCP──▶ upstream :9000 (answers "hello" and closes)
```

## The problem

When the upstream finishes, `l4proxy.(*Handler).proxy` shuts down the writing
side of the downstream connection with `CloseWrite()`. Without TLS that sends a
TCP FIN. With the `tls` handler in front, the downstream is a `*tls.Conn`, and
[`tls.Conn.CloseWrite`](https://pkg.go.dev/crypto/tls#Conn.CloseWrite) only
sends `close_notify`. As documented, it "does not call CloseWrite on the
underlying connection", so no FIN is ever sent.

Anything that only looks at TCP never sees the server finish. For example, a
layer 4 load balancer in front of Caddy, or a client that does not act on
`close_notify`. The connection then stays open until that peer closes it on its
own. The same applies towards TLS upstreams when the downstream finishes first.

## Run it

Requirements: Docker with Compose. Caddy is built from source in the image.

```sh
./run.sh                                                               # upstream caddy-l4 master
./run.sh https://github.com/cruizba/caddy-l4 fix/tls-close-write-fin   # any git repository and branch
```

The client reads through TLS until `close_notify`. Then it waits 3 s for a FIN on
the raw TCP socket and keeps the connection open for 10 s without sending
anything. A `tcpdump` running in Caddy's network namespace prints every FIN and
RST on :8443. `run.sh` exits with 1 when the bug reproduces.

### caddy-l4 master

```
caddy-l4: https://github.com/mholt/caddy-l4 master 42db569 proxy_protocol: Adjust go-proxyproto's internal buffer size (#450)
15:42:18.120 client: connected 172.19.0.4:36298 -> 172.19.0.3:8443
15:42:18.126 client: read "hello\n" through TLS, then close_notify
15:42:21.127 client: BUG: no TCP FIN within 3s after close_notify; for TCP the connection is still open
15:42:21.127 client: keeping the connection open for 10s without sending anything
15:42:31.136 client: closing
>>> FIN/RST packets on caddy:8443 (the client closes after its hold time):
2026-10-02 15:42:31.137650 IP 172.19.0.4.36298 > 172.19.0.3.8443: Flags [F.], ...
2026-10-02 15:42:31.137973 IP 172.19.0.3.8443 > 172.19.0.4.36298: Flags [F.], ...
```

The upstream finished at 15:42:18. Caddy's FIN only appears 13 s later, as a
reply to the client's own FIN.

### With the fix (`cruizba/caddy-l4` branch `fix/tls-close-write-fin`)

```
caddy-l4: https://github.com/cruizba/caddy-l4 fix/tls-close-write-fin f70dac7 proxy: Send a TCP FIN after close_notify when half-closing TLS
15:44:32.012 client: connected 172.19.0.4:50330 -> 172.19.0.3:8443
15:44:32.021 client: read "hello\n" through TLS, then close_notify
15:44:32.021 client: OK: TCP FIN received, the server shut down its side of the connection
>>> FIN/RST packets on caddy:8443 (the client closes after its hold time):
2026-10-02 15:44:32.020995 IP 172.19.0.3.8443 > 172.19.0.4.50330: Flags [F.], ...
2026-10-02 15:44:42.027808 IP 172.19.0.4.50330 > 172.19.0.3.8443: Flags [F.], ...
```

## Without Docker

`local.sh` builds a Caddy binary with xcaddy (installed, or through `go run`)
and runs the same setup on the host. It needs Go and `socat`.

```sh
./local.sh                          # github.com/mholt/caddy-l4@master
./local.sh /path/to/caddy-l4        # a local checkout
```

## Files

- `caddy/Dockerfile`: builds Caddy with caddy-l4 cloned from `CADDY_L4_REPO` at `CADDY_L4_REF`.
- `caddy/caddy.json`: the layer4 `tls` + `proxy` route, with an internal certificate for `localhost`.
- `client/main.go`: the TLS client that checks for the FIN.
- `docker-compose.yml`: `upstream` (socat), `caddy`, `tcpdump` (netshoot) and `client`.

## Related

- Fix: [`cruizba/caddy-l4` branch `fix/tls-close-write-fin`](https://github.com/cruizba/caddy-l4/tree/fix/tls-close-write-fin).
- Once a connection is half-closed, the proxy waits without a deadline for the other side to finish:
  [caddy-l4-repro-halfclose-timeout](https://github.com/cruizba/caddy-l4-repro-halfclose-timeout).
