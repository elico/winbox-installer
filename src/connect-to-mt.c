/*
 * connect-to-mt.c - URL handler for winbox:// and mt:// links (C version).
 *
 *   winbox://[user[:password]@]host[:port]
 *
 * Same behaviour as connect-to-mt.go:
 *   - host: hostname or IPv4; port defaults to 8291
 *   - user info is split at the LAST '@', so a password may contain a raw
 *     '@', '/', '?' or '#'; percent-encoding (%40) is decoded ('+' is NOT a space)
 *   - user and password are passed to WinBox only when a password is present
 *   - WinBox is looked up next to this exe, then in %ProgramFiles%\winbox
 *   - errors are shown in a message box (GUI build, no console window)
 *
 * Build (MinGW-w64):
 *   x86_64-w64-mingw32-gcc -O2 -s -municode -mwindows -o connect-to-mt-64-c.exe connect-to-mt.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_PORT "8291"
#define APP_TITLE    "MikroTik URL Handler"

typedef struct {
    char *host;
    char *port;
    char *user;
    char *pass;
    int   has_pass;
} target;

/* ---------- portable parsing (UTF-8 strings) ---------- */

static void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) abort();
    return p;
}

static char *dupn(const char *s, size_t n) {
    char *d = xmalloc(n + 1);
    memcpy(d, s, n);
    d[n] = '\0';
    return d;
}

static int is_digit(char c) { return c >= '0' && c <= '9'; }
static int is_alnum(char c) { return is_digit(c) || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static int is_space(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\v' || c == '\f'; }

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int prefix_icase(const char *s, const char *prefix) {
    for (; *prefix; s++, prefix++) {
        char a = *s, b = *prefix;
        if (a >= 'A' && a <= 'Z') a += 'a' - 'A';
        if (a != b) return 0;
    }
    return 1;
}

/* Percent-decode s[0..n). On an invalid escape, return the raw string
 * unchanged (same fallback as the Go version). */
static char *unescape(const char *s, size_t n) {
    char *out = xmalloc(n + 1);
    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == '%') {
            int hi, lo;
            if (i + 2 < n &&
                (hi = hexval(s[i + 1])) >= 0 && (lo = hexval(s[i + 2])) >= 0) {
                out[j++] = (char)(hi * 16 + lo);
                i += 2;
            } else {
                memcpy(out, s, n);
                out[n] = '\0';
                return out;
            }
        } else {
            out[j++] = s[i];
        }
    }
    out[j] = '\0';
    return out;
}

/* Strict dotted-quad: 4 parts, 0-255, no leading zeros. */
static int valid_ipv4(const char *s) {
    int parts = 0;
    while (1) {
        int digits = 0, val = 0;
        const char *start = s;
        while (is_digit(*s)) {
            val = val * 10 + (*s - '0');
            if (++digits > 3) return 0;
            s++;
        }
        if (digits == 0 || val > 255 || (digits > 1 && *start == '0')) return 0;
        parts++;
        if (*s == '\0') return parts == 4;
        if (*s != '.' || parts == 4) return 0;
        s++;
    }
}

/* Labels of letters, digits and '-', not starting/ending with '-'; one optional trailing dot. */
static int valid_hostname(const char *s) {
    size_t len = strlen(s);
    if (len > 1 && s[len - 1] == '.') len--;
    if (len == 0) return 0;
    size_t i = 0;
    while (i < len) {
        size_t start = i;
        while (i < len && s[i] != '.') {
            if (!is_alnum(s[i]) && s[i] != '-') return 0;
            i++;
        }
        if (i == start || s[start] == '-' || s[i - 1] == '-') return 0;
        if (i < len) {          /* at a '.' */
            i++;
            if (i == len) return 0;   /* empty label */
        }
    }
    return 1;
}

/* Anything made only of digits and dots must be a valid IPv4 address. */
static int valid_host(const char *h) {
    const char *p = h;
    while (*p && (is_digit(*p) || *p == '.')) p++;
    if (*p == '\0') return valid_ipv4(h);
    return valid_hostname(h);
}

static int valid_port(const char *p) {
    long v = 0;
    if (*p == '\0') return 0;
    for (; *p; p++) {
        if (!is_digit(*p)) return 0;
        v = v * 10 + (*p - '0');
        if (v > 65535) return 0;
    }
    return v >= 1;
}

static char *format_err(const char *fmt, const char *arg) {
    size_t n = strlen(fmt) + strlen(arg) + 1;
    char *e = xmalloc(n);
    snprintf(e, n, fmt, arg);
    return e;
}

/* Returns NULL on success, or an allocated error message. */
static char *parse_url(const char *raw, target *t) {
    memset(t, 0, sizeof(*t));

    /* trim whitespace */
    while (is_space(*raw)) raw++;
    size_t n = strlen(raw);
    while (n > 0 && is_space(raw[n - 1])) n--;

    const char *s = raw;
    if (prefix_icase(s, "winbox:")) s += 7;
    else if (prefix_icase(s, "mt:")) s += 3;
    if (s[0] == '/' && s[1] == '/') s += 2;
    n -= (size_t)(s - raw);

    /* user info ends at the LAST '@' */
    const char *at = NULL;
    for (size_t i = 0; i < n; i++)
        if (s[i] == '@') at = s + i;
    if (at) {
        size_t ilen = (size_t)(at - s);
        const char *colon = memchr(s, ':', ilen);
        if (colon) {
            t->user = unescape(s, (size_t)(colon - s));
            t->pass = unescape(colon + 1, ilen - (size_t)(colon - s) - 1);
            t->has_pass = 1;
        } else {
            t->user = unescape(s, ilen);
            t->pass = dupn("", 0);
        }
        n -= ilen + 1;
        s = at + 1;
    } else {
        t->user = dupn("", 0);
        t->pass = dupn("", 0);
    }

    /* drop path / query / fragment */
    for (size_t i = 0; i < n; i++)
        if (s[i] == '/' || s[i] == '?' || s[i] == '#') { n = i; break; }
    if (n == 0) return dupn("No host specified.", 18);

    char *hp = dupn(s, n);
    char *colon = strrchr(hp, ':');
    if (colon && strchr(hp, ':') != colon) colon = NULL;   /* >1 ':' (IPv6, MAC): no port split, host is rejected below */
    if (colon) {
        *colon = '\0';
        t->host = dupn(hp, strlen(hp));
        t->port = colon[1] ? dupn(colon + 1, strlen(colon + 1)) : dupn(DEFAULT_PORT, 4);
    } else {
        t->host = dupn(hp, n);
        t->port = dupn(DEFAULT_PORT, 4);
    }
    free(hp);

    if (!valid_port(t->port)) return format_err("Invalid port: %s", t->port);
    if (!valid_host(t->host)) return format_err("Invalid host: %s", t->host);

    /* normalise port (e.g. 08291 -> 8291) */
    char buf[8];
    snprintf(buf, sizeof(buf), "%ld", strtol(t->port, NULL, 10));
    free(t->port);
    t->port = dupn(buf, strlen(buf));
    return NULL;
}

/* Append one argument to dst, quoted by the Windows command-line rules
 * (CommandLineToArgvW / MSVCRT), so it reaches WinBox unchanged.
 * dst must have room for 2*strlen(a)+3 more bytes. */
static char *append_arg(char *dst, const char *a) {
    if (*a && !strpbrk(a, " \t\n\v\"")) {
        size_t l = strlen(a);
        memcpy(dst, a, l);
        return dst + l;
    }
    *dst++ = '"';
    for (;;) {
        size_t bs = 0;
        while (*a == '\\') { bs++; a++; }
        if (*a == '\0') {                       /* backslashes before closing quote: double them */
            for (size_t k = 0; k < bs * 2; k++) *dst++ = '\\';
            break;
        } else if (*a == '"') {                 /* escape backslashes and the quote */
            for (size_t k = 0; k < bs * 2 + 1; k++) *dst++ = '\\';
            *dst++ = '"';
        } else {
            for (size_t k = 0; k < bs; k++) *dst++ = '\\';
            *dst++ = *a;
        }
        a++;
    }
    *dst++ = '"';
    return dst;
}

/* Build the full command line: "<winbox>" host:port [user password] */
static char *build_cmdline(const char *exe, const target *t) {
    size_t cap = 2 * (strlen(exe) + strlen(t->host) + strlen(t->port) + strlen(t->user) + strlen(t->pass)) + 32;
    char *cmd = xmalloc(cap), *p = cmd;
    char *hostport = xmalloc(strlen(t->host) + strlen(t->port) + 2);
    sprintf(hostport, "%s:%s", t->host, t->port);

    *p++ = '"';                                 /* program name: plain quotes, no escaping rules */
    memcpy(p, exe, strlen(exe)); p += strlen(exe);
    *p++ = '"';
    *p++ = ' ';
    p = append_arg(p, hostport);
    if (t->user[0] && t->has_pass) {
        *p++ = ' ';
        p = append_arg(p, t->user);
        *p++ = ' ';
        p = append_arg(p, t->pass);
    }
    *p = '\0';
    free(hostport);
    return cmd;
}

#ifndef CONNECT_TO_MT_TEST
/* ---------- Windows part ---------- */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>

static wchar_t *to_wide(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    wchar_t *w = xmalloc((size_t)n * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}

static char *to_utf8(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    char *s = xmalloc((size_t)n);
    WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL);
    return s;
}

static void message(const char *msg, UINT icon) {
    wchar_t *w = to_wide(msg);
    MessageBoxW(NULL, w, L"" APP_TITLE, icon);
    free(w);
}

static void fail(const char *msg) {
    message(msg, MB_ICONERROR);
    exit(1);
}

static int is_file(const wchar_t *p) {
    DWORD a = GetFileAttributesW(p);
    return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

#define PATHBUF 32768

/* Next to this exe first, then %ProgramFiles%\winbox. Returns NULL if not found. */
static wchar_t *find_winbox(char **tried) {
    static const wchar_t *names[] = { L"WinBox.exe", L"winbox64.exe" };
    wchar_t *self = xmalloc(PATHBUF * sizeof(wchar_t));
    DWORD n = GetModuleFileNameW(NULL, self, PATHBUF);
    if (n == 0 || n >= PATHBUF) fail("Cannot locate own executable.");
    wchar_t *slash = wcsrchr(self, L'\\');
    if (slash) *slash = L'\0';

    wchar_t pf[PATHBUF];
    DWORD pn = GetEnvironmentVariableW(L"ProgramFiles", pf, PATHBUF);
    const wchar_t *dirs[2] = { self, NULL };
    wchar_t pfdir[PATHBUF + 16];
    if (pn > 0 && pn < PATHBUF) {
        _snwprintf(pfdir, PATHBUF + 16, L"%ls\\winbox", pf);
        pfdir[PATHBUF + 15] = L'\0';
        dirs[1] = pfdir;
    }

    size_t tcap = 1, tlen = 0;
    *tried = xmalloc(1);
    (*tried)[0] = '\0';
    for (int d = 0; d < 2; d++) {
        if (!dirs[d]) continue;
        for (int i = 0; i < 2; i++) {
            size_t len = wcslen(dirs[d]) + wcslen(names[i]) + 2;
            wchar_t *p = xmalloc(len * sizeof(wchar_t));
            _snwprintf(p, len, L"%ls\\%ls", dirs[d], names[i]);
            p[len - 1] = L'\0';
            if (is_file(p)) { free(self); return p; }
            char *u = to_utf8(p);
            tcap += strlen(u) + 1;
            *tried = realloc(*tried, tcap);
            if (!*tried) abort();
            tlen += (size_t)sprintf(*tried + tlen, "\n%s", u);
            free(u);
            free(p);
        }
    }
    free(self);
    return NULL;
}

int wmain(int argc, wchar_t **argv) {
    const wchar_t *wurl = NULL;
    for (int i = 1; i < argc; i++) {
        if (!wcscmp(argv[i], L"-h") || !wcscmp(argv[i], L"--help") || !wcscmp(argv[i], L"/?")) {
            message("Usage:\n  connect-to-mt [-url] winbox://[user[:password]@]host[:port]\n\n"
                    "Schemes: winbox://, mt://\nDefault port: " DEFAULT_PORT, MB_ICONINFORMATION);
            return 0;
        } else if (!wcscmp(argv[i], L"-url") || !wcscmp(argv[i], L"--url")) {
            if (i + 1 < argc) wurl = argv[++i];
        } else if (!wcsncmp(argv[i], L"-url=", 5)) {
            wurl = argv[i] + 5;
        } else if (!wcsncmp(argv[i], L"--url=", 6)) {
            wurl = argv[i] + 6;
        } else if (!wurl) {
            wurl = argv[i];
        }
    }
    if (!wurl || !*wurl) fail("No URL specified.");

    char *url = to_utf8(wurl);
    target t;
    char *err = parse_url(url, &t);
    if (err) fail(err);

    char *tried = NULL;
    wchar_t *winbox = find_winbox(&tried);
    if (!winbox) {
        char *msg = xmalloc(strlen(tried) + 64);
        sprintf(msg, "WinBox not found. Looked for:%s", tried);
        fail(msg);
    }

    char *exe = to_utf8(winbox);
    char *cmd = build_cmdline(exe, &t);
    wchar_t *wcmd = to_wide(cmd);

    wchar_t *dir = _wcsdup(winbox);
    wchar_t *slash = wcsrchr(dir, L'\\');
    if (slash) *slash = L'\0';

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcessW(winbox, wcmd, NULL, NULL, FALSE, 0, NULL, dir, &si, &pi)) {
        char buf[64];
        snprintf(buf, sizeof(buf), " (error %lu)", (unsigned long)GetLastError());
        char *msg = xmalloc(strlen(exe) + 64);
        sprintf(msg, "Failed to launch %s%s", exe, buf);
        fail(msg);
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return 0;
}
#endif
