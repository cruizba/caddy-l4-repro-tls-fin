// Command client connects to a caddy-l4 TLS listener, reads until the server's
// close_notify and then checks whether the server also shut down the TCP
// connection (FIN). It behaves like a peer that only looks at TCP, such as a
// layer 4 load balancer: it keeps the connection open without sending anything
// and only closes when -hold elapses.
//
// Exit status: 0 when the FIN arrives, 1 when it does not (the bug).
package main

import (
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"time"
)

func main() {
	addr := flag.String("addr", "caddy:8443", "address of the layer4 TLS listener")
	serverName := flag.String("servername", "localhost", "TLS server name")
	wait := flag.Duration("wait", 3*time.Second, "how long to wait for the TCP FIN after close_notify")
	hold := flag.Duration("hold", 10*time.Second, "how long to keep the connection open afterwards")
	flag.Parse()

	logf := func(format string, args ...any) {
		fmt.Printf("%s client: %s\n", time.Now().Format("15:04:05.000"), fmt.Sprintf(format, args...))
	}

	raw, err := net.Dial("tcp", *addr)
	if err != nil {
		logf("dial: %v", err)
		os.Exit(2)
	}
	defer raw.Close()
	logf("connected %s -> %s", raw.LocalAddr(), raw.RemoteAddr())

	conn := tls.Client(raw, &tls.Config{ServerName: *serverName, InsecureSkipVerify: true}) //nolint:gosec // reproduction only
	data, err := io.ReadAll(conn)
	if err != nil {
		logf("reading through TLS: %v", err)
		os.Exit(2)
	}
	logf("read %q through TLS, then close_notify", data)

	bug := false
	_ = raw.SetReadDeadline(time.Now().Add(*wait))
	_, err = raw.Read(make([]byte, 1))
	switch {
	case errors.Is(err, io.EOF):
		logf("OK: TCP FIN received, the server shut down its side of the connection")
	case errors.Is(err, os.ErrDeadlineExceeded):
		logf("BUG: no TCP FIN within %s after close_notify; for TCP the connection is still open", *wait)
		bug = true
	default:
		logf("raw read: %v", err)
	}

	logf("keeping the connection open for %s without sending anything", *hold)
	time.Sleep(*hold)
	logf("closing")
	if bug {
		os.Exit(1)
	}
}
