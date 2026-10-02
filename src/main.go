package main

import (
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
	"syscall"
)

var hostRegex = regexp.MustCompile(`^[a-zA-Z0-9.-]+$`)

func main() {
	var rawURL string
	flag.StringVar(&rawURL, "url", "", "Connection URL")
	flag.Parse()

	if rawURL == "" && flag.NArg() > 0 {
		rawURL = flag.Arg(0)
	}

	if rawURL == "" {
		showError("No URL specified.")
		os.Exit(1)
	}

	// Clean scheme and trailing paths
	trimmed := regexp.MustCompile(`^(?i)(winbox|mt)://`).ReplaceAllString(rawURL, "")
	trimmed = regexp.MustCompile(`[/?#].*$`).ReplaceAllString(trimmed, "")

	// Parse with standard URL parser by supplying dummy http scheme
	u, err := url.Parse("http://" + trimmed)
	if err != nil {
		showError(fmt.Sprintf("Invalid URL format: %v", err))
		os.Exit(1)
	}

	host := u.Hostname()
	port := u.Port()
	if port == "" {
		port = "8291"
	} else {
		p, err := strconv.Atoi(port)
		if err != nil || p < 1 || p > 65535 {
			showError(fmt.Sprintf("Invalid port: %s", port))
			os.Exit(1)
		}
	}

	if !hostRegex.MatchString(host) {
		showError(fmt.Sprintf("Invalid host: %s", host))
		os.Exit(1)
	}

	// Locate WinBox executable relative to connect-to-mt-64.exe
	exeDir, _ := filepath.Abs(filepath.Dir(os.Args[0]))
	winboxPath := filepath.Join(exeDir, "WinBox.exe")
	if _, err := os.Stat(winboxPath); os.IsNotExist(err) {
		winboxPath = filepath.Join(exeDir, "winbox64.exe")
	}

	target := net.JoinHostPort(host, port)
	var args []string

	user := u.User.Username()
	pass, hasPass := u.User.Password()

	if user != "" && hasPass {
		args = []string{target, user, pass}
	} else {
		args = []string{target}
	}

	cmd := exec.Command(winboxPath, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := cmd.Start(); err != nil {
		showError(fmt.Sprintf("Failed to launch %s: %v", winboxPath, err))
		os.Exit(1)
	}
}

func showError(msg string) {
	user32 := syscall.NewLazyDLL("user32.dll")
	procMessageBox := user32.NewProc("MessageBoxW")
	title, _ := syscall.UTF16PtrFromString("MikroTik URL Handler")
	text, _ := syscall.UTF16PtrFromString(msg)
	procMessageBox.Call(0, uintptr(unsafePointer(text)), uintptr(unsafePointer(title)), 0x10) // MB_ICONERROR
}

func unsafePointer(p *uint16) uintptr {
	return uintptr(uintptr(unsafe.Pointer(p)))
}
