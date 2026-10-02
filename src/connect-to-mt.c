#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlwapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#pragma comment(lib, "shlwapi.lib")

static void print_usage(const char *prog) {
    printf("MikroTik WinBox URL Handler CLI\n\n");
    printf("Usage:\n");
    printf("  %s -url <winbox://...>\n", prog);
    printf("  %s <winbox://...>\n", prog);
    printf("  %s --help\n\n", prog);
    printf("Supported schemes: winbox://, mt://\n");
    printf("Format: [scheme://][user[:password]@]hostname[:port]\n");
}

static void url_decode(char *dst, const char *src) {
    char a, b;
    while (*src) {
        if ((*src == '%') &&
            ((a = src[1]) && (b = src[2])) &&
            (isxdigit((unsigned char)a) && isxdigit((unsigned char)b))) {
            if (a >= 'a') a -= 'a' - 'A';
            if (a >= 'A') a -= ('A' - 10);
            else a -= '0';
            if (b >= 'a') b -= 'a' - 'A';
            if (b >= 'A') b -= ('A' - 10);
            else b -= '0';
            *dst++ = 16 * a + b;
            src += 3;
        } else if (*src == '+') {
            *dst++ = ' ';
            src++;
        } else {
            *dst++ = *src++;
        }
    }
    *dst = '\0';
}

static int is_valid_hostname_char(char c) {
    return isalnum((unsigned char)c) || c == '.' || c == '-' || c == '_';
}

static int validate_hostname(const char *h) {
    if (!h || *h == '\0') return 0;
    size_t len = strlen(h);
    if (len > 253) return 0;
    for (size_t i = 0; i < len; i++) {
        if (!is_valid_hostname_char(h[i])) return 0;
    }
    return 1;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    char rawUrl[1024] = {0};
    int verbose = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            verbose = 1;
        } else if (strcmp(argv[i], "-url") == 0 || strcmp(argv[i], "--url") == 0) {
            if (i + 1 < argc) {
                strncpy(rawUrl, argv[++i], sizeof(rawUrl) - 1);
            }
        } else if (rawUrl[0] == '\0' && argv[i][0] != '-') {
            strncpy(rawUrl, argv[i], sizeof(rawUrl) - 1);
        }
    }

    if (rawUrl[0] == '\0') {
        fprintf(stderr, "Error: No target URL provided.\n");
        return 1;
    }

    // Strip scheme prefix (case-insensitive)
    char *p = rawUrl;
    if (_strnicmp(p, "winbox://", 9) == 0) {
        p += 9;
    } else if (_strnicmp(p, "mt://", 5) == 0) {
        p += 5;
    }

    // Strip path, query, or anchor
    char *delim = strpbrk(p, "/?#");
    if (delim) *delim = '\0';

    if (*p == '\0') {
        fprintf(stderr, "Error: Empty connection target.\n");
        return 1;
    }

    char user[128] = {0};
    char pass[128] = {0};
    char host[256] = {0};
    char port[16] = "8291";

    // Parse user[:pass]@
    char *at = strchr(p, '@');
    char *host_part = p;
    if (at) {
        *at = '\0';
        host_part = at + 1;
        char *colon = strchr(p, ':');
        if (colon) {
            *colon = '\0';
            url_decode(user, p);
            url_decode(pass, colon + 1);
        } else {
            url_decode(user, p);
        }
    }

    // Parse host[:port]
    char *colon = strrchr(host_part, ':');
    if (colon) {
        *colon = '\0';
        strncpy(host, host_part, sizeof(host) - 1);
        int parsed_port = atoi(colon + 1);
        if (parsed_port >= 1 && parsed_port <= 65535) {
            snprintf(port, sizeof(port), "%d", parsed_port);
        } else {
            fprintf(stderr, "Error: Invalid port '%s'. Must be between 1 and 65535.\n", colon + 1);
            return 1;
        }
    } else {
        strncpy(host, host_part, sizeof(host) - 1);
    }

    if (!validate_hostname(host)) {
        fprintf(stderr, "Error: Invalid hostname or IP address '%s'.\n", host);
        return 1;
    }

    // Locate WinBox executable relative to connect-to-mt-64.exe directory
    char winboxPath[MAX_PATH];
    GetModuleFileNameA(NULL, winboxPath, MAX_PATH);
    PathRemoveFileSpecA(winboxPath);
    PathAppendA(winboxPath, "WinBox.exe");

    if (GetFileAttributesA(winboxPath) == INVALID_FILE_ATTRIBUTES) {
        // Try winbox64.exe in same directory
        GetModuleFileNameA(NULL, winboxPath, MAX_PATH);
        PathRemoveFileSpecA(winboxPath);
        PathAppendA(winboxPath, "winbox64.exe");

        if (GetFileAttributesA(winboxPath) == INVALID_FILE_ATTRIBUTES) {
            // Fallback to default Program Files
            strncpy(winboxPath, "C:\\Program Files\\winbox\\WinBox.exe", sizeof(winboxPath) - 1);
        }
    }

    // Construct command line arguments
    // WinBox syntax: <executable> <ip[:port]> [user] [password]
    char cmdArgs[1024];
    if (user[0] != '\0') {
        snprintf(cmdArgs, sizeof(cmdArgs), "\"%s\" %s:%s \"%s\" \"%s\"", winboxPath, host, port, user, pass);
    } else {
        snprintf(cmdArgs, sizeof(cmdArgs), "\"%s\" %s:%s", winboxPath, host, port);
    }

    if (verbose) {
        printf("Resolved WinBox: %s\n", winboxPath);
        printf("Target:          %s:%s\n", host, port);
        if (user[0] != '\0') {
            printf("User:            %s\n", user);
        }
        printf("Executing:       %s\n", cmdArgs);
    }

    // Launch WinBox process detached
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcessA(NULL, cmdArgs, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        fprintf(stderr, "Error: Failed to spawn WinBox (code %lu) at '%s'\n", GetLastError(), winboxPath);
        return 1;
    }

    // Do not block terminal; let Winbox run independently
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    if (verbose) {
        printf("WinBox launched successfully.\n");
    }

    return 0;
}
