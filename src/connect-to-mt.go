//go:build windows

// connect-to-mt: URL handler for winbox:// and mt:// links.
//
//	winbox://[user[:password]@]host[:port]
//
// host can be a hostname or an IPv4 address.
// Characters in the user or password that are special in URLs may be
// percent-encoded (e.g. %40 for '@'). A raw '/', '?', '#' or '@' inside the
// password also works, because user info is split at the LAST '@'.
//
// Build:
//
//	GOOS=windows GOARCH=amd64 go build -ldflags "-H=windowsgui -s -w" -o connect-to-mt-64.exe
package main

import (
	"errors"
	"flag"
	"fmt"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/sys/windows"
)

const defaultPort = "8291"

var (
	schemeRe   = regexp.MustCompile(`^(?i)(winbox|mt):(//)?`)
	hostnameRe = regexp.MustCompile(`^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*\.?$`)
	numericRe  = regexp.MustCompile(`^[0-9.]+$`)
)

type target struct {
	connectTo string // what WinBox gets as its first argument
	user      string
	pass      string
	hasPass   bool
}

func main() {
	var rawURL string
	flag.StringVar(&rawURL, "url", "", "Connection URL: winbox://[user[:pass]@]host[:port]")
	flag.Parse()
	if rawURL == "" && flag.NArg() > 0 {
		rawURL = flag.Arg(0)
	}
	if rawURL == "" {
		fail("No URL specified.")
	}

	t, err := parse(rawURL)
	if err != nil {
		fail(err.Error())
	}

	winbox, err := findWinBox()
	if err != nil {
		fail(err.Error())
	}

	args := []string{t.connectTo}
	if t.user != "" && t.hasPass {
		args = append(args, t.user, t.pass)
	}

	cmd := exec.Command(winbox, args...)
	cmd.Dir = filepath.Dir(winbox)
	if err := cmd.Start(); err != nil {
		fail(fmt.Sprintf("Failed to launch %s: %v", winbox, err))
	}
	_ = cmd.Process.Release()
}

func parse(raw string) (target, error) {
	var t target

	s := schemeRe.ReplaceAllString(strings.TrimSpace(raw), "")

	// User info ends at the last '@', so a password may contain '@', '/', '?' or '#'.
	if i := strings.LastIndex(s, "@"); i >= 0 {
		userinfo := s[:i]
		s = s[i+1:]
		user, pass, hasPass := strings.Cut(userinfo, ":")
		t.user = unescape(user)
		t.pass = unescape(pass)
		t.hasPass = hasPass
	}

	// Drop any path / query / fragment (browsers often append a trailing '/').
	if i := strings.IndexAny(s, "/?#"); i >= 0 {
		s = s[:i]
	}
	if s == "" {
		return t, errors.New("No host specified.")
	}

	host, port := s, ""
	if h, p, err := net.SplitHostPort(s); err == nil {
		host, port = h, p
	}

	if port == "" {
		port = defaultPort
	} else if p, err := strconv.Atoi(port); err != nil || p < 1 || p > 65535 {
		return t, fmt.Errorf("Invalid port: %s", port)
	}

	if !validHost(host) {
		return t, fmt.Errorf("Invalid host: %s", host)
	}

	t.connectTo = net.JoinHostPort(host, port)
	return t, nil
}

// validHost accepts an IPv4 address or a DNS hostname. Anything made only of
// digits and dots must be a valid IPv4 address (rejects 10.0.0.256, 1.2.3).
func validHost(h string) bool {
	if numericRe.MatchString(h) {
		ip := net.ParseIP(h)
		return ip != nil && ip.To4() != nil
	}
	return hostnameRe.MatchString(h)
}

// unescape percent-decodes s, falling back to the raw string if it isn't
// valid percent-encoding (e.g. a password that contains a literal '%').
func unescape(s string) string {
	if u, err := url.PathUnescape(s); err == nil {
		return u
	}
	return s
}

func findWinBox() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("Cannot locate own executable: %v", err)
	}
	dir := filepath.Dir(exe)
	candidates := []string{"WinBox.exe", "winbox64.exe"}
	for _, name := range candidates {
		p := filepath.Join(dir, name)
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p, nil
		}
	}
	return "", fmt.Errorf("WinBox not found. Put %s next to\n%s", strings.Join(candidates, " or "), exe)
}

// fail shows an error dialog (there is no console in a -H=windowsgui build) and exits.
func fail(msg string) {
	title, _ := windows.UTF16PtrFromString("MikroTik URL Handler")
	text, _ := windows.UTF16PtrFromString(msg)
	windows.MessageBox(0, text, title, windows.MB_ICONERROR)
	os.Exit(1)
}
