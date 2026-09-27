#include "net_asset_server.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET socket_t;
#define close_socket closesocket
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int socket_t;
#define INVALID_SOCKET (-1)
#define SOCKET_ERROR (-1)
#define close_socket close
#endif

#define MAX_ASSETS 64u
#define MAX_FILE_BYTES (16u * 1024u * 1024u)

static void release_assets(asset_server_entry *entries, size_t count)
{
    for (size_t i = 0; i < count; ++i) free((void *)entries[i].data);
}

static int load_manifest(const char *manifest, asset_server_entry *entries, size_t *count)
{
    FILE *list = fopen(manifest, "r");
    char line[512];
    size_t base = 0;
    if (!list) return -1;
    for (size_t i = 0; manifest[i]; ++i)
        if (manifest[i] == '/' || manifest[i] == '\\') base = i + 1;
    *count = 0;
    while (fgets(line, sizeof line, list)) {
        char *name, *end;
        unsigned long id;
        char path[1024];
        FILE *file;
        long length;
        uint8_t *data;
        size_t n = strlen(line);
        if (n && line[n - 1] != '\n' && !feof(list)) goto fail;
        if (n && line[n - 1] == '\n') line[--n] = 0;
        if (n && line[n - 1] == '\r') line[--n] = 0;
        if (!n || line[0] == '#') continue;
        if (*count == MAX_ASSETS) goto fail;
        errno = 0;
        id = strtoul(line, &end, 10);
        if (errno || end == line || id > UINT32_MAX || *end != ',') goto fail;
        name = end + 1;
        if (!*name || strstr(name, "..") || strchr(name, '/') ||
            strchr(name, '\\') || strchr(name, ':')) goto fail;
        for (size_t i = 0; i < *count; ++i)
            if (entries[i].id == (uint32_t)id) goto fail;
        if (base + strlen(name) >= sizeof path) goto fail;
        memcpy(path, manifest, base);
        strcpy(path + base, name);
        file = fopen(path, "rb");
        if (!file) goto fail;
        if (fseek(file, 0, SEEK_END) || (length = ftell(file)) <= 0 ||
            (unsigned long)length > MAX_FILE_BYTES || fseek(file, 0, SEEK_SET)) {
            fclose(file);
            goto fail;
        }
        data = malloc((size_t)length);
        if (!data) {
            fclose(file);
            goto fail;
        }
        if (fread(data, 1, (size_t)length, file) != (size_t)length) {
            free(data);
            fclose(file);
            goto fail;
        }
        fclose(file);
        entries[*count].id = (uint32_t)id;
        entries[*count].data = data;
        entries[*count].length = (size_t)length;
        ++*count;
    }
    fclose(list);
    return *count ? 0 : -1;
fail:
    fclose(list);
    release_assets(entries, *count);
    *count = 0;
    return -1;
}

int main(int argc, char **argv)
{
    asset_server_entry entries[MAX_ASSETS] = {0};
    asset_server server;
    size_t count;
    socket_t sock;
    struct sockaddr_in bind_addr = {0};
    char *port_end;
    unsigned long port;
    uint8_t request[1500], response[ASST_HEADER_BYTES + ASST_MAX_PAYLOAD];
    if (argc != 3) {
        fprintf(stderr, "usage: asset_server manifest.csv udp_port\n");
        return 2;
    }
    errno = 0;
    port = strtoul(argv[2], &port_end, 10);
    if (errno || !*argv[2] || *port_end || port == 0 || port > 65535 ||
        load_manifest(argv[1], entries, &count)) {
        fprintf(stderr, "invalid port or manifest\n");
        return 2;
    }
#ifdef _WIN32
    WSADATA startup;
    if (WSAStartup(MAKEWORD(2, 2), &startup)) return 1;
#endif
    sock = socket(AF_INET, SOCK_DGRAM, 0);
    bind_addr.sin_family = AF_INET;
    bind_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    bind_addr.sin_port = htons((uint16_t)port);
    if (sock == INVALID_SOCKET ||
        bind(sock, (struct sockaddr *)&bind_addr, sizeof bind_addr) == SOCKET_ERROR) {
        fprintf(stderr, "UDP bind failed\n");
        release_assets(entries, count);
        return 1;
    }
    server.entries = entries;
    server.count = count;
    fprintf(stdout, "ASST server: %zu assets, UDP %lu\n", count, port);
    fflush(stdout);
    for (;;) {
        struct sockaddr_in peer;
#ifdef _WIN32
        int peer_len = sizeof peer;
        int received = recvfrom(sock, (char *)request, sizeof request, 0,
                                (struct sockaddr *)&peer, &peer_len);
#else
        socklen_t peer_len = sizeof peer;
        ssize_t received = recvfrom(sock, request, sizeof request, 0,
                                    (struct sockaddr *)&peer, &peer_len);
#endif
        size_t sent = 0;
        int result;
        if (received < 0) continue;
        result = asset_server_handle_get(&server, request, (size_t)received,
                                         response, sizeof response, &sent);
        if (result == -2 && received == ASST_HEADER_BYTES) {
            asst_header header;
            if (!asst_decode(&header, request) && header.type == ASST_GET) {
                header.type = ASST_ERROR;
                header.payload_len = 0;
                header.flags = 0;
                header.payload_crc32 = 0;
                if (!asst_encode(response, &header)) sent = ASST_HEADER_BYTES;
            }
        }
        if (sent) sendto(sock, (const char *)response, (int)sent, 0,
                         (struct sockaddr *)&peer, peer_len);
    }
    close_socket(sock);
    release_assets(entries, count);
    return 0;
}
