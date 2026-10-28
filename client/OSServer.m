#import "OSServer.h"
#import "OSHUD.h"
#import <UIKit/UIKit.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>
#include <sys/stat.h>

#include "cJSON.h"
#include "mbedtls/ssl.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/pk.h"
#include "mbedtls/ecp.h"
#include "mbedtls/sha256.h"
#include "mbedtls/error.h"
#include "mbedtls/md.h"

#define OS_PORT 53317
#define OS_PROTOCOL_VERSION "2.2"
#define OS_RECEIVED_DIR "/var/mobile/Library/OldSend/Received"
#define OS_MAX_FILES 32
#define OS_MAX_JSON (8 * 1024 * 1024)

NSString * const OSServerDidUpdateNotification = @"OSServerDidUpdateNotification";
NSString * const OSServerSendDidFinishNotification = @"OSServerSendDidFinishNotification";
NSString * const OSServerSendProgressNotification = @"OSServerSendProgressNotification";
NSString * const OSServerDidReceiveTextNotification = @"OSServerDidReceiveTextNotification";

typedef struct {
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_x509_crt cert;
    mbedtls_pk_context key;
    char fingerprint[65];
    int ready;
} OSIdentity;

typedef struct {
    char id[80];
    char token[40];
    char name[256];
    char type[64];
    char path[512];
    long long size;
    char sha256[65];
    int uploaded;
    int isMessage;
} OSFileEntry;

typedef struct {
    int active;
    char sessionId[40];
    int count;
    int remaining;
    OSFileEntry files[OS_MAX_FILES];
} OSSession;

typedef struct {
    char method[16];
    char path[1024];
    long long contentLength;
    int chunked;
    int closeConnection;
} OSRequest;

static OSSession gSession;
static char gLastSessionId[40];
static volatile BOOL gCancelSend = NO;
static volatile int gSendFD = -1;

static void os_file_log(NSString *line) {
    FILE *file = fopen("/var/mobile/oldsend.log", "a");
    if (file == NULL) return;
    fprintf(file, "%s\n", [line UTF8String]);
    fflush(file);
    fclose(file);
}

static void os_logf(OSServer *server, NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    [server appendLog:line];
    [line release];
}

static NSString *os_json_escape(NSString *value) {
    if (value == nil) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:[value length] + 8];
    NSUInteger i, length = [value length];
    for (i = 0; i < length; i++) {
        unichar c = [value characterAtIndex:i];
        if (c == '"' || c == '\\') {
            [out appendFormat:@"\\%C", c];
        } else if (c == '\n') {
            [out appendString:@"\\n"];
        } else if (c == '\r') {
            [out appendString:@"\\r"];
        } else if (c == '\t') {
            [out appendString:@"\\t"];
        } else if (c < 0x20) {
            [out appendFormat:@"\\u%04x", (unsigned)c];
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    return out;
}

static void os_mbed_error(char *dst, size_t size, int ret) {
    if (ret == 0) {
        dst[0] = '\0';
        return;
    }
    mbedtls_strerror(ret, dst, size);
}

static int os_write_file(NSString *path, const unsigned char *bytes, size_t length) {
    NSData *data = [NSData dataWithBytes:bytes length:length];
    return [data writeToFile:path atomically:YES] ? 0 : -1;
}

static int os_fingerprint(mbedtls_x509_crt *cert, char out[65]) {
    unsigned char hash[32];
    int ret = mbedtls_sha256_ret(cert->raw.p, cert->raw.len, hash, 0);
    if (ret != 0) return ret;
    int i;
    for (i = 0; i < 32; i++) {
        sprintf(out + i * 2, "%02X", hash[i]);
    }
    out[64] = '\0';
    return 0;
}

static int os_identity_generate(OSIdentity *id, NSString *dir, char *err, size_t errlen) {
    int ret;
    unsigned char certPem[8192];
    unsigned char keyPem[8192];
    mbedtls_x509write_cert writer;
    mbedtls_mpi serial;

    mbedtls_x509write_crt_init(&writer);
    mbedtls_mpi_init(&serial);

    ret = mbedtls_pk_setup(&id->key, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY));
    if (ret != 0) {
        os_mbed_error(err, errlen, ret);
        goto cleanup;
    }

    ret = mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1, mbedtls_pk_ec(id->key),
                              mbedtls_ctr_drbg_random, &id->drbg);
    if (ret != 0) {
        os_mbed_error(err, errlen, ret);
        goto cleanup;
    }

    mbedtls_x509write_crt_set_version(&writer, MBEDTLS_X509_CRT_VERSION_3);
    mbedtls_x509write_crt_set_md_alg(&writer, MBEDTLS_MD_SHA256);
    mbedtls_x509write_crt_set_subject_key(&writer, &id->key);
    mbedtls_x509write_crt_set_issuer_key(&writer, &id->key);

    ret = mbedtls_x509write_crt_set_subject_name(&writer, "CN=OldSend");
    if (ret != 0) goto fail;

    ret = mbedtls_x509write_crt_set_issuer_name(&writer, "CN=OldSend");
    if (ret != 0) goto fail;

    /* LocalSend's own certificates use rcgen's 1975..4096 validity, so a
       device whose clock is wrong still accepts this certificate. */
    ret = mbedtls_x509write_crt_set_validity(&writer, "19750101000000", "40960101000000");
    if (ret != 0) goto fail;

    ret = mbedtls_x509write_crt_set_basic_constraints(&writer, 0, 0);
    if (ret != 0) goto fail;

    ret = mbedtls_x509write_crt_set_key_usage(&writer,
            MBEDTLS_X509_KU_DIGITAL_SIGNATURE | MBEDTLS_X509_KU_KEY_ENCIPHERMENT);
    if (ret != 0) goto fail;

    {
        unsigned char serialBytes[8];
        ret = mbedtls_ctr_drbg_random(&id->drbg, serialBytes, sizeof serialBytes);
        if (ret != 0) goto fail;
        serialBytes[0] &= 0x7f;
        if (serialBytes[0] == 0) serialBytes[0] = 1;
        ret = mbedtls_mpi_read_binary(&serial, serialBytes, sizeof serialBytes);
        if (ret != 0) goto fail;
        ret = mbedtls_x509write_crt_set_serial(&writer, &serial);
        if (ret != 0) goto fail;
    }

    ret = mbedtls_x509write_crt_pem(&writer, certPem, sizeof certPem,
                                    mbedtls_ctr_drbg_random, &id->drbg);
    if (ret != 0) goto fail;

    ret = mbedtls_pk_write_key_pem(&id->key, keyPem, sizeof keyPem);
    if (ret != 0) goto fail;

    {
        NSString *certPath = [dir stringByAppendingPathComponent:@"cert.pem"];
        NSString *keyPath = [dir stringByAppendingPathComponent:@"key.pem"];
        size_t certLen = strlen((const char *)certPem) + 1;
        size_t keyLen = strlen((const char *)keyPem) + 1;
        if (os_write_file(certPath, certPem, certLen) != 0 ||
            os_write_file(keyPath, keyPem, keyLen) != 0) {
            snprintf(err, errlen, "cannot write identity files");
            ret = -1;
            goto cleanup;
        }
        ret = mbedtls_x509_crt_parse(&id->cert, certPem, certLen);
        if (ret != 0) goto fail;
        ret = os_fingerprint(&id->cert, id->fingerprint);
        if (ret != 0) goto fail;
    }

    id->ready = 1;
    ret = 0;
    goto cleanup;

fail:
    os_mbed_error(err, errlen, ret);
cleanup:
    mbedtls_x509write_crt_free(&writer);
    mbedtls_mpi_free(&serial);
    return ret;
}

static int os_identity_init(OSIdentity *id, NSString *dir, char *err, size_t errlen) {
    int ret;
    static const unsigned char personalization[] = "oldsend";
    NSString *certPath;
    NSString *keyPath;
    NSData *certData;
    NSData *keyData;

    memset(id, 0, sizeof *id);
    mbedtls_entropy_init(&id->entropy);
    mbedtls_ctr_drbg_init(&id->drbg);
    mbedtls_x509_crt_init(&id->cert);
    mbedtls_pk_init(&id->key);

    ret = mbedtls_ctr_drbg_seed(&id->drbg, mbedtls_entropy_func, &id->entropy,
                                personalization, sizeof personalization - 1);
    if (ret != 0) {
        os_mbed_error(err, errlen, ret);
        return ret;
    }

    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
        snprintf(err, errlen, "cannot create %s", [dir UTF8String]);
        return -1;
    }

    certPath = [dir stringByAppendingPathComponent:@"cert.pem"];
    keyPath = [dir stringByAppendingPathComponent:@"key.pem"];
    certData = [NSData dataWithContentsOfFile:certPath];
    keyData = [NSData dataWithContentsOfFile:keyPath];

    if ([certData length] > 0 && [keyData length] > 0) {
        ret = mbedtls_x509_crt_parse(&id->cert, [certData bytes], [certData length]);
        if (ret == 0) {
            ret = mbedtls_pk_parse_key(&id->key, [keyData bytes], [keyData length], NULL, 0);
        }
        if (ret == 0) {
            ret = os_fingerprint(&id->cert, id->fingerprint);
        }
        if (ret == 0) {
            id->ready = 1;
            return 0;
        }

        mbedtls_x509_crt_free(&id->cert);
        mbedtls_x509_crt_init(&id->cert);
        mbedtls_pk_free(&id->key);
        mbedtls_pk_init(&id->key);
    }

    return os_identity_generate(id, dir, err, errlen);
}

static void os_identity_free(OSIdentity *id) {
    if (id == NULL) return;
    mbedtls_x509_crt_free(&id->cert);
    mbedtls_pk_free(&id->key);
    mbedtls_ctr_drbg_free(&id->drbg);
    mbedtls_entropy_free(&id->entropy);
    free(id);
}

static int os_bio_send(void *ctx, const unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
    ssize_t n;
    do {
        n = send(fd, buf, len, 0);
    } while (n < 0 && errno == EINTR);
    if (n < 0) return MBEDTLS_ERR_NET_SEND_FAILED;
    return (int)n;
}

static int os_bio_recv(void *ctx, unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
    ssize_t n;
    do {
        n = recv(fd, buf, len, 0);
    } while (n < 0 && errno == EINTR);
    if (n < 0) return MBEDTLS_ERR_NET_RECV_FAILED;
    if (n == 0) return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
    return (int)n;
}

static int os_read_line(mbedtls_ssl_context *ssl, char *buf, size_t cap) {
    size_t i = 0;
    while (i + 1 < cap) {
        unsigned char c;
        int n = mbedtls_ssl_read(ssl, &c, 1);
        if (n <= 0) return -1;
        if (c == '\n') {
            if (i > 0 && buf[i - 1] == '\r') i--;
            buf[i] = '\0';
            return (int)i;
        }
        buf[i++] = (char)c;
    }
    buf[cap - 1] = '\0';
    return -1;
}

static int os_ssl_write_all(mbedtls_ssl_context *ssl, const void *data, size_t length) {
    const unsigned char *p = (const unsigned char *)data;
    while (length > 0) {
        int n = mbedtls_ssl_write(ssl, p, length);
        if (n <= 0) return n;
        p += n;
        length -= (size_t)n;
    }
    return 0;
}

static int os_ssl_read_exact(mbedtls_ssl_context *ssl, unsigned char *buf, size_t length) {
    size_t offset = 0;
    while (offset < length) {
        int n = mbedtls_ssl_read(ssl, buf + offset, length - offset);
        if (n <= 0) return -1;
        offset += (size_t)n;
    }
    return 0;
}

static int os_random_hex(OSIdentity *identity, char *out, size_t bytes) {
    unsigned char random[32];
    size_t i;
    if (bytes > sizeof random) return -1;
    if (mbedtls_ctr_drbg_random(&identity->drbg, random, bytes) != 0) return -1;
    for (i = 0; i < bytes; i++) {
        sprintf(out + i * 2, "%02x", random[i]);
    }
    out[bytes * 2] = '\0';
    return 0;
}

static void os_url_decode(char *text) {
    char *read = text;
    char *write = text;
    while (*read) {
        if (*read == '%' && isxdigit((unsigned char)read[1]) && isxdigit((unsigned char)read[2])) {
            char hex[3] = { read[1], read[2], 0 };
            *write++ = (char)strtol(hex, NULL, 16);
            read += 3;
        } else if (*read == '+') {
            *write++ = ' ';
            read++;
        } else {
            *write++ = *read++;
        }
    }
    *write = '\0';
}

static int os_query_value(const char *path, const char *key, char *out, size_t cap) {
    const char *query = strchr(path, '?');
    size_t keyLength = strlen(key);
    if (query == NULL) return 0;
    query++;

    while (*query) {
        const char *amp = strchr(query, '&');
        size_t partLength = amp ? (size_t)(amp - query) : strlen(query);
        if (partLength > keyLength && strncmp(query, key, keyLength) == 0 &&
            query[keyLength] == '=') {
            size_t valueLength = partLength - keyLength - 1;
            if (valueLength >= cap) valueLength = cap - 1;
            memcpy(out, query + keyLength + 1, valueLength);
            out[valueLength] = '\0';
            os_url_decode(out);
            return 1;
        }
        if (amp == NULL) break;
        query = amp + 1;
    }
    return 0;
}

static int os_read_chunked_alloc(mbedtls_ssl_context *ssl, unsigned char **out, size_t *outLen) {
    size_t capacity = 4096;
    size_t length = 0;
    unsigned char *buffer = (unsigned char *)malloc(capacity);
    if (buffer == NULL) return -1;

    for (;;) {
        char line[128];
        unsigned long chunkSize;
        char *extension;

        if (os_read_line(ssl, line, sizeof line) < 0) goto fail;
        extension = strchr(line, ';');
        if (extension != NULL) *extension = '\0';
        chunkSize = strtoul(line, NULL, 16);

        if (chunkSize == 0) {
            while (os_read_line(ssl, line, sizeof line) > 0) {
                /* trailers */
            }
            break;
        }

        if (length + chunkSize + 1 > OS_MAX_JSON) goto fail;
        if (length + chunkSize + 1 > capacity) {
            while (capacity < length + chunkSize + 1) capacity *= 2;
            buffer = (unsigned char *)realloc(buffer, capacity);
            if (buffer == NULL) return -1;
        }
        if (os_ssl_read_exact(ssl, buffer + length, chunkSize) != 0) goto fail;
        length += chunkSize;

        {
            unsigned char crlf[2];
            if (os_ssl_read_exact(ssl, crlf, 2) != 0) goto fail;
        }
    }

    buffer[length] = '\0';
    *out = buffer;
    *outLen = length;
    return 0;

fail:
    free(buffer);
    return -1;
}

static int os_read_body_alloc(mbedtls_ssl_context *ssl, OSRequest *request,
                              unsigned char **out, size_t *outLen) {
    if (request->chunked) {
        return os_read_chunked_alloc(ssl, out, outLen);
    }
    if (request->contentLength < 0 || request->contentLength > OS_MAX_JSON) return -1;

    {
        size_t length = (size_t)request->contentLength;
        unsigned char *buffer = (unsigned char *)malloc(length + 1);
        if (buffer == NULL) return -1;
        if (length > 0 && os_ssl_read_exact(ssl, buffer, length) != 0) {
            free(buffer);
            return -1;
        }
        buffer[length] = '\0';
        *out = buffer;
        *outLen = length;
        return 0;
    }
}

typedef void (*OSProgressCallback)(void *context, long long written, long long total);

typedef struct {
    OSServer *server;
    long long lastReported;
} OSProgressContext;

static void os_progress_cb(void *context, long long written, long long total) {
    OSProgressContext *progress = (OSProgressContext *)context;
    NSArray *info;

    if (written != total && written - progress->lastReported < 131072) return;
    progress->lastReported = written;
    info = [NSArray arrayWithObjects:
            [NSNumber numberWithLongLong:written],
            [NSNumber numberWithLongLong:total], nil];
    [progress->server performSelectorOnMainThread:@selector(updateUploadProgressInfo:)
                                       withObject:info
                                    waitUntilDone:NO];
}

static int os_stream_body(mbedtls_ssl_context *ssl, OSRequest *request, FILE *file,
                          mbedtls_sha256_context *sha, long long *written,
                          long long expectedTotal, OSProgressCallback progress,
                          void *progressContext) {
    unsigned char buffer[16384];
    *written = 0;

    if (request->chunked) {
        for (;;) {
            char line[128];
            unsigned long chunkSize;
            char *extension;

            if (os_read_line(ssl, line, sizeof line) < 0) return -1;
            extension = strchr(line, ';');
            if (extension != NULL) *extension = '\0';
            chunkSize = strtoul(line, NULL, 16);

            if (chunkSize == 0) {
                while (os_read_line(ssl, line, sizeof line) > 0) {
                    /* trailers */
                }
                return 0;
            }

            {
                size_t left = chunkSize;
                while (left > 0) {
                    size_t want = left > sizeof buffer ? sizeof buffer : left;
                    if (os_ssl_read_exact(ssl, buffer, want) != 0) return -1;
                    if (fwrite(buffer, 1, want, file) != want) return -1;
                    mbedtls_sha256_update_ret(sha, buffer, want);
                    left -= want;
                    *written += (long long)want;
                    if (progress != NULL) progress(progressContext, *written, expectedTotal);
                }
            }

            {
                unsigned char crlf[2];
                if (os_ssl_read_exact(ssl, crlf, 2) != 0) return -1;
            }
        }
    }

    {
        long long left = request->contentLength;
        while (left > 0) {
            size_t want = left > (long long)sizeof buffer ? sizeof buffer : (size_t)left;
            if (os_ssl_read_exact(ssl, buffer, want) != 0) return -1;
            if (fwrite(buffer, 1, want, file) != want) return -1;
            mbedtls_sha256_update_ret(sha, buffer, want);
            left -= (long long)want;
            *written += (long long)want;
            if (progress != NULL) progress(progressContext, *written, expectedTotal);
        }
    }
    return 0;
}

static void os_sanitize_filename(const char *input, char *output, size_t capacity) {
    const char *name = input != NULL ? input : "";
    const char *slash = strrchr(name, '/');
    size_t out = 0;

    if (slash != NULL) name = slash + 1;
    slash = strrchr(name, '\\');
    if (slash != NULL) name = slash + 1;

    while (*name && out + 1 < capacity) {
        unsigned char c = (unsigned char)*name++;
        if (c < 0x20 || c == 0x7f) continue;
        output[out++] = (char)c;
    }
    output[out] = '\0';

    if (out == 0 || strcmp(output, ".") == 0 || strcmp(output, "..") == 0) {
        snprintf(output, capacity, "file");
    }
}

static int os_sha256_hex(const unsigned char *data, size_t length, char out[65]) {
    unsigned char digest[32];
    int i;
    if (mbedtls_sha256_ret(data, length, digest, 0) != 0) return -1;
    for (i = 0; i < 32; i++) {
        sprintf(out + i * 2, "%02X", digest[i]);
    }
    out[64] = '\0';
    return 0;
}

static int os_tcp_connect(const char *ip, int port, int timeoutMs) {
    struct sockaddr_in address;
    int fd;
    int flags;
    int result;
    int error = 0;
    socklen_t errorLength = sizeof error;
    fd_set writeSet;
    struct timeval timeout;

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    memset(&address, 0, sizeof address);
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, ip, &address.sin_addr) != 1) {
        close(fd);
        return -1;
    }

    flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    result = connect(fd, (struct sockaddr *)&address, sizeof address);
    if (result < 0) {
        if (errno != EINPROGRESS) {
            close(fd);
            return -1;
        }
        FD_ZERO(&writeSet);
        FD_SET(fd, &writeSet);
        timeout.tv_sec = timeoutMs / 1000;
        timeout.tv_usec = (timeoutMs % 1000) * 1000;
        result = select(fd + 1, NULL, &writeSet, NULL, &timeout);
        if (result <= 0) {
            close(fd);
            return -1;
        }
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &errorLength) != 0 || error != 0) {
            close(fd);
            return -1;
        }
    }

    fcntl(fd, F_SETFL, flags);
    {
        int one = 1;
        struct timeval ioTimeout;
        ioTimeout.tv_sec = 10;
        ioTimeout.tv_usec = 0;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &ioTimeout, sizeof ioTimeout);
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &ioTimeout, sizeof ioTimeout);
    }
    return fd;
}

static int os_register_peer(OSIdentity *identity, mbedtls_ssl_config *config,
                            const char *ip, int port, const char *expectedFingerprint,
                            const char *body, char *status, size_t statusLength) {
    int fd;
    mbedtls_ssl_context ssl;
    int ret;
    char header[512];
    char response[512];

    if (gCancelSend) return -10;

    fd = os_tcp_connect(ip, port, 5000);
    if (fd < 0) return -1;
    gSendFD = fd;

    mbedtls_ssl_init(&ssl);
    ret = mbedtls_ssl_setup(&ssl, config);
    if (ret != 0) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -2;
    }
    mbedtls_ssl_set_bio(&ssl, &fd, os_bio_send, os_bio_recv, NULL);

    ret = mbedtls_ssl_handshake(&ssl);
    if (ret != 0) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -3;
    }

    {
        const mbedtls_x509_crt *peer = mbedtls_ssl_get_peer_cert(&ssl);
        char fingerprint[65];
        if (peer == NULL || os_sha256_hex(peer->raw.p, peer->raw.len, fingerprint) != 0) {
            mbedtls_ssl_free(&ssl);
            close(fd);
            return -4;
        }
        if (expectedFingerprint != NULL && expectedFingerprint[0] != '\0' &&
            strcasecmp(fingerprint, expectedFingerprint) != 0) {
            mbedtls_ssl_free(&ssl);
            close(fd);
            return -5;
        }
    }

    snprintf(header, sizeof header,
             "POST /api/localsend/v2/register HTTP/1.1\r\n"
             "Host: %s:%d\r\n"
             "Content-Type: application/json\r\n"
             "Content-Length: %lu\r\n"
             "Connection: close\r\n"
             "\r\n",
             ip, port, (unsigned long)strlen(body));

    if (os_ssl_write_all(&ssl, header, strlen(header)) != 0 ||
        os_ssl_write_all(&ssl, body, strlen(body)) != 0) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -6;
    }

    ret = mbedtls_ssl_read(&ssl, (unsigned char *)response, sizeof response - 1);
    if (ret > 0) {
        response[ret] = '\0';
        if (status != NULL && statusLength > 0) {
            char *lineEnd = strstr(response, "\r\n");
            if (lineEnd != NULL) *lineEnd = '\0';
            snprintf(status, statusLength, "%s", response);
        }
    }

    mbedtls_ssl_close_notify(&ssl);
    mbedtls_ssl_free(&ssl);
    close(fd);
    return 0;
}

typedef struct {
    OSServer *server;
    long long base;
    long long total;
    long long lastReported;
} OSSendProgressContext;

static void os_send_progress_cb(void *context, long long written, long long total) {
    OSSendProgressContext *progress = (OSSendProgressContext *)context;
    long long overallWritten = progress->base + written;
    NSNumber *value;

    (void)total;
    if (progress->total <= 0) return;
    if (overallWritten != progress->total &&
        overallWritten - progress->lastReported < 131072) {
        return;
    }
    progress->lastReported = overallWritten;
    value = [NSNumber numberWithFloat:(float)((double)overallWritten /
                                              (double)progress->total)];
    [progress->server performSelectorOnMainThread:@selector(deliverSendProgress:)
                                       withObject:value
                                    waitUntilDone:NO];
}

static int os_client_request(OSIdentity *identity, mbedtls_ssl_config *config,
                             const char *ip, int port, const char *expectedFingerprint,
                             const char *path, const char *contentType,
                             const void *body, size_t bodyLength,
                             const char *filePath, long long fileSize,
                             NSMutableData *response, int *statusOut,
                             void (*progress)(void *, long long, long long),
                             void *progressContext) {
    int fd;
    mbedtls_ssl_context ssl;
    int ret;
    char header[1024];
    char line[512];
    int status = 0;
    long long contentLength = -1;

    fd = os_tcp_connect(ip, port, 5000);
    if (fd < 0) return -1;

    mbedtls_ssl_init(&ssl);
    ret = mbedtls_ssl_setup(&ssl, config);
    if (ret != 0) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -2;
    }
    mbedtls_ssl_set_bio(&ssl, &fd, os_bio_send, os_bio_recv, NULL);

    ret = mbedtls_ssl_handshake(&ssl);
    if (ret != 0) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -3;
    }

    {
        const mbedtls_x509_crt *peer = mbedtls_ssl_get_peer_cert(&ssl);
        char fingerprint[65];
        if (peer == NULL || os_sha256_hex(peer->raw.p, peer->raw.len, fingerprint) != 0) {
            mbedtls_ssl_free(&ssl);
            close(fd);
            return -4;
        }
        if (expectedFingerprint != NULL && expectedFingerprint[0] != '\0' &&
            strcasecmp(fingerprint, expectedFingerprint) != 0) {
            mbedtls_ssl_free(&ssl);
            close(fd);
            return -5;
        }
    }

    {
        long long total = filePath != NULL ? fileSize : (long long)bodyLength;
        snprintf(header, sizeof header,
                 "POST %s HTTP/1.1\r\n"
                 "Host: %s:%d\r\n"
                 "Content-Type: %s\r\n"
                 "Content-Length: %lld\r\n"
                 "Connection: close\r\n"
                 "\r\n",
                 path, ip, port, contentType, total);
    }

    if (os_ssl_write_all(&ssl, header, strlen(header)) != 0) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -6;
    }

    if (filePath != NULL) {
        FILE *file = fopen(filePath, "rb");
        unsigned char buffer[16384];
        size_t n;
        long long sent = 0;
        if (file == NULL) {
            mbedtls_ssl_free(&ssl);
            close(fd);
            return -7;
        }
        while ((n = fread(buffer, 1, sizeof buffer, file)) > 0) {
            if (os_ssl_write_all(&ssl, buffer, n) != 0) {
                fclose(file);
                mbedtls_ssl_free(&ssl);
                close(fd);
                return -8;
            }
            sent += (long long)n;
            if (gCancelSend) {
                fclose(file);
                mbedtls_ssl_free(&ssl);
                close(fd);
                return -10;
            }
            if (progress != NULL) progress(progressContext, sent, fileSize);
        }
        fclose(file);
    } else if (bodyLength > 0) {
        if (os_ssl_write_all(&ssl, body, bodyLength) != 0) {
            mbedtls_ssl_free(&ssl);
            close(fd);
            return -8;
        }
    }

    if (gCancelSend) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -10;
    }

    if (os_read_line(&ssl, line, sizeof line) < 0 ||
        sscanf(line, "HTTP/%*s %d", &status) != 1) {
        mbedtls_ssl_free(&ssl);
        close(fd);
        return -9;
    }

    while (os_read_line(&ssl, line, sizeof line) > 0) {
        if (strncasecmp(line, "Content-Length:", 15) == 0) {
            contentLength = strtoll(line + 15, NULL, 10);
        }
    }

    if (response != nil && contentLength > 0 && contentLength < 2 * 1024 * 1024) {
        long long left = contentLength;
        unsigned char buffer[4096];
        while (left > 0) {
            size_t want = left > (long long)sizeof buffer ? sizeof buffer : (size_t)left;
            int got = mbedtls_ssl_read(&ssl, buffer, want);
            if (got <= 0) break;
            [response appendBytes:buffer length:(NSUInteger)got];
            left -= got;
        }
    }

    if (statusOut != NULL) *statusOut = status;

    mbedtls_ssl_close_notify(&ssl);
    mbedtls_ssl_free(&ssl);
    close(fd);
    return 0;
}

static void os_make_id(char out[33]) {
    int i;
    for (i = 0; i < 16; i++) {
        unsigned char byte = (unsigned char)(arc4random() & 0xff);
        sprintf(out + i * 2, "%02x", byte);
    }
    out[32] = '\0';
}

static NSInteger os_file_date_compare(id first, id second, void *context) {
    NSDate *firstDate = [first objectForKey:@"date"];
    NSDate *secondDate = [second objectForKey:@"date"];
    NSComparisonResult result = [secondDate compare:firstDate];
    if (result == NSOrderedSame) {
        return [[first objectForKey:@"name"] compare:[second objectForKey:@"name"]];
    }
    return result;
}

static NSString *os_unique_path(NSString *directory, NSString *name) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = [directory stringByAppendingPathComponent:name];
    if (![manager fileExistsAtPath:path]) return path;

    NSString *base = [name stringByDeletingPathExtension];
    NSString *extension = [name pathExtension];
    int i;
    for (i = 1; i < 10000; i++) {
        NSString *candidate;
        if ([extension length] > 0) {
            candidate = [NSString stringWithFormat:@"%@ (%d).%@", base, i, extension];
        } else {
            candidate = [NSString stringWithFormat:@"%@ (%d)", base, i];
        }
        path = [directory stringByAppendingPathComponent:candidate];
        if (![manager fileExistsAtPath:path]) return path;
    }
    return [directory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@-%u", name, (unsigned)arc4random()]];
}

@interface OSServer () <UIAlertViewDelegate>
- (void)saveNextPhoto;
- (void)enqueuePhotoBatch:(NSArray *)items;
- (void)setSessionActiveFlag:(NSNumber *)active;
- (void)beginSessionProgressWithTotal:(NSNumber *)total;
- (void)finishReceivingText;
- (void)startReceiveWatchdog;
- (void)stopReceiveWatchdog;
- (void)touchReceiveActivity;
- (void)handleCancelledSession;
- (void)receiveWatchdogTick:(NSTimer *)timer;
- (void)showReceiveCompleteAlert:(NSNumber *)count;
- (void)queueReceiveCompleteAlert:(NSNumber *)count;
- (void)showPendingReceiveCompleteAlert;
@end

@implementation OSServer

+ (OSServer *)shared {
    static OSServer *shared = nil;
    if (shared == nil) {
        shared = [[OSServer alloc] init];
    }
    return shared;
}

+ (NSString *)localIPAddress {
    struct ifaddrs *list = NULL;
    NSString *en0 = nil;
    NSString *other = nil;

    if (getifaddrs(&list) != 0) return @"0.0.0.0";

    struct ifaddrs *p;
    for (p = list; p != NULL; p = p->ifa_next) {
        if (p->ifa_addr == NULL || p->ifa_addr->sa_family != AF_INET) continue;
        if (strcmp(p->ifa_name, "lo0") == 0) continue;

        struct sockaddr_in *sin = (struct sockaddr_in *)p->ifa_addr;
        char text[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &sin->sin_addr, text, sizeof text) == NULL) continue;

        NSString *ip = [NSString stringWithUTF8String:text];
        if (strcmp(p->ifa_name, "en0") == 0) {
            en0 = ip;
        } else if (other == nil) {
            other = ip;
        }
    }
    freeifaddrs(list);

    if (en0 != nil) return en0;
    if (other != nil) return other;
    return @"0.0.0.0";
}

- (id)init {
    if ((self = [super init])) {
        _log = [[NSMutableArray alloc] init];
        _status = [NSLocalizedString(@"status.stopped", nil) retain];
        _alias = [@"iPod touch" copy];
        _model = [@"iPod touch" copy];
        _localIP = [@"0.0.0.0" copy];
        _fingerprint = [@"" copy];
        _devices = [[NSMutableArray alloc] init];
        _receiveStatus = [NSLocalizedString(@"status.waiting", nil) copy];
        _uploadName = [@"" copy];
        _photoCondition = [[NSCondition alloc] init];
        _decisionCondition = [[NSCondition alloc] init];
        _receivedTexts = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (NSString *)generateAlias {
    NSString *adjectivesText = NSLocalizedString(@"alias.adjectives", nil);
    NSString *nounsText = NSLocalizedString(@"alias.nouns", nil);
    NSArray *adjectives = [adjectivesText componentsSeparatedByString:@"|"];
    NSArray *nouns = [nounsText componentsSeparatedByString:@"|"];
    NSString *separator = NSLocalizedString(@"alias.separator", nil);

    if ([adjectives count] == 0 || [nouns count] == 0) {
        return @"OldSend";
    }

    NSString *adjective = [adjectives objectAtIndex:(arc4random() % [adjectives count])];
    NSString *noun = [nouns objectAtIndex:(arc4random() % [nouns count])];
    return [NSString stringWithFormat:@"%@%@%@", adjective, separator, noun];
}

- (NSString *)alias {
    return _alias;
}

- (void)setAlias:(NSString *)alias {
    if ([alias length] == 0) return;
    if ([alias isEqualToString:_alias]) return;

    /* Settings runs on the main thread while the network threads may still
       read the old string; leaving it alive avoids a use-after-free. */
    _alias = [alias copy];
    [[NSUserDefaults standardUserDefaults] setObject:_alias forKey:@"device_alias"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self announceNow];
    [self appendLog:[NSString stringWithFormat:@"Alias changed to %@", _alias]];
}

- (NSArray *)devices {
    return _devices;
}

- (BOOL)deleteReceivedFile:(NSDictionary *)file {
    NSString *path = [file objectForKey:@"path"];
    NSString *name = [file objectForKey:@"name"];
    NSString *marker;
    BOOL removed;

    if ([path length] == 0) return NO;
    removed = [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    if (removed) {
        marker = [[[@OS_RECEIVED_DIR stringByAppendingPathComponent:@".saved"]
                   stringByAppendingPathComponent:name] copy];
        [[NSFileManager defaultManager] removeItemAtPath:marker error:NULL];
        [marker release];
    }
    return removed;
}

- (NSArray *)receivedFiles {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = @OS_RECEIVED_DIR;
    NSArray *names = [manager contentsOfDirectoryAtPath:directory error:NULL];
    NSMutableArray *result = [NSMutableArray array];

    for (NSString *name in names) {
        NSString *path;
        NSString *extension;
        NSString *type = @"file";
        NSDictionary *attributes;
        BOOL isDirectory = NO;

        if ([name hasPrefix:@"."]) continue;
        path = [directory stringByAppendingPathComponent:name];
        if (![manager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) continue;

        attributes = [manager attributesOfItemAtPath:path error:NULL];
        extension = [[name pathExtension] lowercaseString];

        if ([extension isEqualToString:@"jpg"] ||
            [extension isEqualToString:@"jpeg"] ||
            [extension isEqualToString:@"png"] ||
            [extension isEqualToString:@"gif"]) {
            type = @"image";
        } else if ([extension isEqualToString:@"mp4"] ||
                   [extension isEqualToString:@"mov"] ||
                   [extension isEqualToString:@"m4v"]) {
            type = @"video";
        } else if ([extension isEqualToString:@"mp3"] ||
                   [extension isEqualToString:@"m4a"] ||
                   [extension isEqualToString:@"aac"] ||
                   [extension isEqualToString:@"wav"]) {
            type = @"audio";
        }

        [result addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            name, @"name",
            path, @"path",
            type, @"type",
            [attributes objectForKey:NSFileSize] ?: [NSNumber numberWithLongLong:0], @"size",
            [attributes objectForKey:NSFileModificationDate] ?: [NSDate date], @"date",
            nil]];
    }

    [result sortUsingFunction:os_file_date_compare context:NULL];
    return result;
}

- (NSString *)receiveStatus {
    return _receiveStatus;
}

- (BOOL)isSavingToPhotos {
    return _savingCount > 0;
}

- (BOOL)isReceiving {
    return _receiving;
}

- (BOOL)isSessionActive {
    return _sessionActive;
}

- (void)resetReceivedTexts {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(resetReceivedTexts)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    [_receivedTexts removeAllObjects];
}

- (void)addReceivedText:(NSString *)text {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(addReceivedText:)
                               withObject:text
                            waitUntilDone:NO];
        return;
    }
    if ([text length] > 0) {
        [_receivedTexts addObject:text];
    }
}

- (void)showReceivedTexts {
    NSString *combined;

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(showReceivedTexts)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    if ([_receivedTexts count] == 0) return;

    combined = [_receivedTexts componentsJoinedByString:@"\n\n"];
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidReceiveTextNotification
                                                        object:self
                                                      userInfo:[NSDictionary dictionaryWithObject:combined
                                                                                           forKey:@"text"]];
    [_receivedTexts removeAllObjects];
}

- (void)setSessionActiveFlag:(NSNumber *)active {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(setSessionActiveFlag:)
                               withObject:active
                            waitUntilDone:NO];
        return;
    }
    _sessionActive = [active boolValue];
    if (!_sessionActive) {
        _receiving = NO;
        _sessionProgress = 0.0f;
        _sessionBaseBytes = 0;
        _currentFileWritten = 0;
        _sessionTotalBytes = 0;
        if (_savingCount == 0) {
            [self setReceiveStatusText:NSLocalizedString(@"status.waiting", nil)];
        }
        [self stopReceiveWatchdog];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
}

- (void)beginSessionProgressWithTotal:(NSNumber *)total {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(beginSessionProgressWithTotal:)
                               withObject:total
                            waitUntilDone:NO];
        return;
    }
    _sessionActive = YES;
    _sessionTotalBytes = [total longLongValue];
    _sessionBaseBytes = 0;
    _currentFileWritten = 0;
    _sessionProgress = 0.0f;
    _receiving = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
}

- (float)uploadProgress {
    return _sessionProgress;
}

- (NSString *)uploadName {
    return _uploadName;
}

- (void)setReceiveStatusText:(NSString *)text {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(setReceiveStatusText:)
                               withObject:text
                            waitUntilDone:NO];
        return;
    }
    if ([text isEqualToString:_receiveStatus]) return;
    [_receiveStatus release];
    _receiveStatus = [text copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
}

- (void)beginReceivingFile:(NSString *)name {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(beginReceivingFile:)
                               withObject:name
                            waitUntilDone:NO];
        return;
    }
    _receiving = YES;
    _currentFileWritten = 0;
    [self touchReceiveActivity];
    [_uploadName release];
    _uploadName = [name copy];
    [self setReceiveStatusText:[NSString stringWithFormat:
                                NSLocalizedString(@"status.receiving", nil), name]];
}

- (void)updateUploadProgressInfo:(NSArray *)info {
    long long written = [[info objectAtIndex:0] longLongValue];
    long long total = [[info objectAtIndex:1] longLongValue];

    if (_savingCount > 0) return;
    _receiving = YES;
    _currentFileWritten = written;
    _lastReceiveActivity = [NSDate timeIntervalSinceReferenceDate];
    if (_sessionTotalBytes > 0) {
        _sessionProgress = (float)((double)(_sessionBaseBytes + written) /
                                   (double)_sessionTotalBytes);
    } else {
        _sessionProgress = total > 0 ? (float)((double)written / (double)total) : 0.0f;
    }
    if (_sessionProgress < 0.0f) _sessionProgress = 0.0f;
    if (_sessionProgress > 1.0f) _sessionProgress = 1.0f;
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
}

- (void)finishReceivingFile {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(finishReceivingFile)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    _sessionBaseBytes += _currentFileWritten;
    _currentFileWritten = 0;
    if (_sessionTotalBytes > 0) {
        _sessionProgress = (float)((double)_sessionBaseBytes / (double)_sessionTotalBytes);
        if (_sessionProgress > 1.0f) _sessionProgress = 1.0f;
    }
    _receiving = NO;
    [self touchReceiveActivity];
    [self setReceiveStatusText:[NSString stringWithFormat:
                                NSLocalizedString(@"status.received", nil), _uploadName]];
}

- (void)queueReceiveCompleteAlert:(NSNumber *)count {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(queueReceiveCompleteAlert:)
                               withObject:count
                            waitUntilDone:NO];
        return;
    }
    _pendingReceiveCompleteCount = [count integerValue];
    [self showPendingReceiveCompleteAlert];
}

- (void)showPendingReceiveCompleteAlert {
    NSNumber *count;

    if (_pendingReceiveCompleteCount <= 0) return;
    if (_savingCount > 0 || _photoQueueRunning) return;

    count = [NSNumber numberWithInteger:_pendingReceiveCompleteCount];
    _pendingReceiveCompleteCount = 0;
    [self showReceiveCompleteAlert:count];
}

- (void)showReceiveCompleteAlert:(NSNumber *)count {
    UIAlertView *alert;

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(showReceiveCompleteAlert:)
                               withObject:count
                            waitUntilDone:NO];
        return;
    }

    alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"receive.complete_title", nil)
                                       message:[NSString stringWithFormat:
                                                NSLocalizedString(@"receive.complete_message", nil),
                                                [count intValue]]
                                      delegate:nil
                             cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                             otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)finishReceivingText {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(finishReceivingText)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    _sessionBaseBytes += _currentFileWritten;
    _currentFileWritten = 0;
    if (_sessionTotalBytes > 0) {
        _sessionProgress = (float)((double)_sessionBaseBytes / (double)_sessionTotalBytes);
        if (_sessionProgress > 1.0f) _sessionProgress = 1.0f;
    }
    _receiving = NO;
    [self touchReceiveActivity];
    [self setReceiveStatusText:NSLocalizedString(@"status.waiting", nil)];
}

- (void)failReceivingFile {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(failReceivingFile)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    _receiving = NO;
    _sessionActive = NO;
    _sessionProgress = 0.0f;
    _sessionBaseBytes = 0;
    _currentFileWritten = 0;
    _sessionTotalBytes = 0;
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
    [self stopReceiveWatchdog];
    [self setReceiveStatusText:NSLocalizedString(@"status.transfer_interrupted", nil)];
    [self showTransferFailedAlert];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(clearFailureStatus)
                                               object:nil];
    [self performSelector:@selector(clearFailureStatus)
               withObject:nil
               afterDelay:2.0];
    [self resetReceivedTexts];
}

- (void)showTransferFailedAlert {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(showTransferFailedAlert)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"receive.interrupted_title", nil)
                                                        message:NSLocalizedString(@"receive.interrupted_message", nil)
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
                                              otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}

- (void)startReceiveWatchdog {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(startReceiveWatchdog)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    _lastReceiveActivity = [NSDate timeIntervalSinceReferenceDate];
    if (_receiveWatchdog == nil) {
        _receiveWatchdog = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(receiveWatchdogTick:)
                                                          userInfo:nil
                                                           repeats:YES] retain];
    }
}

- (void)stopReceiveWatchdog {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(stopReceiveWatchdog)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    [_receiveWatchdog invalidate];
    [_receiveWatchdog release];
    _receiveWatchdog = nil;
}

- (void)touchReceiveActivity {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(touchReceiveActivity)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    _lastReceiveActivity = [NSDate timeIntervalSinceReferenceDate];
}

- (void)receiveWatchdogTick:(NSTimer *)timer {
    if (!_sessionActive) {
        [self stopReceiveWatchdog];
        return;
    }
    if (_receiving || _savingCount > 0) return;
    if ([NSDate timeIntervalSinceReferenceDate] - _lastReceiveActivity > 8.0) {
        gSession.active = 0;
        gSession.remaining = 0;
        [self failReceivingFile];
        [self stopReceiveWatchdog];
    }
}

- (void)handleCancelledSession {
    [self setSessionActiveFlag:[NSNumber numberWithBool:NO]];
    [self resetReceivedTexts];
}

- (void)clearFailureStatus {
    if (!_sessionActive && !_receiving && _savingCount == 0) {
        [self setReceiveStatusText:NSLocalizedString(@"status.waiting", nil)];
    }
}

- (void)updateSavingStatus {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(updateSavingStatus)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    [_receiveStatus release];
    if (_savingCount > 0) {
        _receiveStatus = [NSLocalizedString(@"status.saving", nil) copy];
        [OSHUD showSaving];
    } else {
        [OSHUD hideSaving];
        if (_receiving) {
            _receiveStatus = [[NSString stringWithFormat:
                               NSLocalizedString(@"status.receiving", nil), _uploadName] copy];
        } else {
            _receiveStatus = [NSLocalizedString(@"status.waiting", nil) copy];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
}

- (void)addDeviceInfo:(NSDictionary *)info {
    NSString *fingerprint;

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(addDeviceInfo:)
                               withObject:info
                            waitUntilDone:NO];
        return;
    }

    fingerprint = [info objectForKey:@"fingerprint"];
    if ([fingerprint length] == 0) return;
    if ([fingerprint isEqualToString:_fingerprint]) return;

    NSUInteger i;
    for (i = 0; i < [_devices count]; i++) {
        NSDictionary *existing = [_devices objectAtIndex:i];
        if ([[existing objectForKey:@"fingerprint"] isEqualToString:fingerprint]) {
            if (![[existing objectForKey:@"ip"] isEqualToString:[info objectForKey:@"ip"]] ||
                ![[existing objectForKey:@"alias"] isEqualToString:[info objectForKey:@"alias"]] ||
                ![[existing objectForKey:@"model"] isEqualToString:[info objectForKey:@"model"]] ||
                ![[existing objectForKey:@"protocol"] isEqualToString:[info objectForKey:@"protocol"]]) {
                [_devices replaceObjectAtIndex:i withObject:info];
                [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                                    object:self];
            }
            return;
        }
    }

    [_devices addObject:info];
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
}

- (NSString *)statusText {
    NSString *state = _running ? NSLocalizedString(@"status.running", nil) : NSLocalizedString(@"status.stopped", nil);
    NSString *fp = _fingerprint;
    if ([fp length] > 16) fp = [fp substringToIndex:16];
    return [NSString stringWithFormat:NSLocalizedString(@"status.line", nil),
            state, _localIP, OS_PORT, _status, fp];
}

- (NSString *)fingerprint {
    return _fingerprint;
}

- (NSString *)localIP {
    return _localIP;
}

- (int)port {
    return OS_PORT;
}

- (NSArray *)logLines {
    return _log;
}

- (void)appendLog:(NSString *)line {
    if (line == nil) return;
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(appendLog:)
                               withObject:line
                            waitUntilDone:NO];
        return;
    }
    os_file_log(line);
    [_log addObject:line];
    while ([_log count] > 200) {
        [_log removeObjectAtIndex:0];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                        object:self];
}

- (NSString *)registerJSON {
    return [NSString stringWithFormat:
            @"{\"alias\":\"%@\",\"version\":\"%s\",\"deviceModel\":\"%@\",\"deviceType\":\"mobile\",\"fingerprint\":\"%@\",\"download\":false}",
            os_json_escape(_alias), OS_PROTOCOL_VERSION, os_json_escape(_model), _fingerprint];
}

- (NSString *)announcementJSON {
    return [NSString stringWithFormat:
            @"{\"alias\":\"%@\",\"version\":\"%s\",\"deviceModel\":\"%@\",\"deviceType\":\"mobile\",\"fingerprint\":\"%@\",\"port\":%d,\"protocol\":\"https\",\"download\":false,\"announce\":true}",
            os_json_escape(_alias), OS_PROTOCOL_VERSION, os_json_escape(_model), _fingerprint, OS_PORT];
}

- (void)announceNow {
    if (!_running) return;

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return;

    unsigned char ttl = 1;
    setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof ttl);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(OS_PORT);
    inet_pton(AF_INET, "224.0.0.167", &addr.sin_addr);

    const char *json = [[self announcementJSON] UTF8String];
    sendto(fd, json, strlen(json), 0, (struct sockaddr *)&addr, sizeof addr);
    close(fd);
}

- (void)probeDevices:(NSArray *)devices {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableArray *offline = [NSMutableArray array];
    NSInteger i;

    for (i = 0; i < (NSInteger)[devices count]; i++) {
        NSDictionary *device = [devices objectAtIndex:i];
        NSString *ip = [device objectForKey:@"ip"];
        int port = [[device objectForKey:@"port"] intValue];
        NSString *fingerprint = [device objectForKey:@"fingerprint"];
        int fd;

        if ([ip length] == 0 || port <= 0 || [fingerprint length] == 0) continue;
        fd = os_tcp_connect([ip UTF8String], port, 500);
        if (fd >= 0) {
            close(fd);
        } else {
            [offline addObject:fingerprint];
        }
    }

    [self performSelectorOnMainThread:@selector(removeOfflineDevices:)
                           withObject:offline
                        waitUntilDone:NO];
    [pool release];
}

- (void)removeOfflineDevices:(NSArray *)fingerprints {
    BOOL changed = NO;
    NSInteger i;

    for (i = (NSInteger)[_devices count] - 1; i >= 0; i--) {
        NSDictionary *device = [_devices objectAtIndex:i];
        if ([fingerprints containsObject:[device objectForKey:@"fingerprint"]]) {
            [_devices removeObjectAtIndex:i];
            changed = YES;
        }
    }
    _refreshingDevices = NO;
    if (changed) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification
                                                            object:self];
    }
}

- (void)refreshDevices {
    NSArray *snapshot;

    if (_refreshingDevices) return;
    _refreshingDevices = YES;
    snapshot = [[NSArray alloc] initWithArray:_devices];
    [NSThread detachNewThreadSelector:@selector(probeDevices:)
                             toTarget:self
                           withObject:snapshot];
    [snapshot release];
}

- (void)announceTimerFired:(NSTimer *)timer {
    [self announceNow];
}

- (void)discoveryThreadMain {
    NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
    OSIdentity *identity = (OSIdentity *)_identity;
    int fd;
    int one = 1;
    struct timeval timeout;
    struct ip_mreq membership;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_ssl_config config;

    typedef struct {
        char fingerprint[65];
        time_t lastSeen;
    } OSCacheEntry;

    OSCacheEntry cache[16];
    memset(cache, 0, sizeof cache);

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        [outerPool release];
        return;
    }

    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one);

    {
        struct sockaddr_in address;
        memset(&address, 0, sizeof address);
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_ANY);
        address.sin_port = htons(OS_PORT);
        if (bind(fd, (struct sockaddr *)&address, sizeof address) != 0) {
            os_logf(self, @"Multicast bind failed: %s", strerror(errno));
            close(fd);
            [outerPool release];
            return;
        }
    }

    memset(&membership, 0, sizeof membership);
    membership.imr_multiaddr.s_addr = inet_addr("224.0.0.167");
    membership.imr_interface.s_addr = htonl(INADDR_ANY);
    setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, sizeof membership);

    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);

    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&drbg);
    mbedtls_ssl_config_init(&config);

    {
        static const unsigned char personalization[] = "oldsend-discovery";
        int ret = mbedtls_ctr_drbg_seed(&drbg, mbedtls_entropy_func, &entropy,
                                        personalization, sizeof personalization - 1);
        if (ret == 0) {
            ret = mbedtls_ssl_config_defaults(&config, MBEDTLS_SSL_IS_CLIENT,
                                              MBEDTLS_SSL_TRANSPORT_STREAM,
                                              MBEDTLS_SSL_PRESET_DEFAULT);
        }
        if (ret == 0) {
            mbedtls_ssl_conf_rng(&config, mbedtls_ctr_drbg_random, &drbg);
            mbedtls_ssl_conf_min_version(&config, MBEDTLS_SSL_MAJOR_VERSION_3,
                                         MBEDTLS_SSL_MINOR_VERSION_3);
            mbedtls_ssl_conf_max_version(&config, MBEDTLS_SSL_MAJOR_VERSION_3,
                                         MBEDTLS_SSL_MINOR_VERSION_3);
            mbedtls_ssl_conf_authmode(&config, MBEDTLS_SSL_VERIFY_NONE);
            ret = mbedtls_ssl_conf_own_cert(&config, &identity->cert, &identity->key);
        }
        if (ret != 0) {
            os_logf(self, @"Discovery init failed (%d)", ret);
            close(fd);
            mbedtls_ssl_config_free(&config);
            mbedtls_ctr_drbg_free(&drbg);
            mbedtls_entropy_free(&entropy);
            [outerPool release];
            return;
        }
    }

    [self appendLog:@"Discovery started"];

    while (_running) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        char buffer[65536];
        struct sockaddr_in from;
        socklen_t fromLength = sizeof from;
        int length = (int)recvfrom(fd, buffer, sizeof buffer - 1, 0,
                                   (struct sockaddr *)&from, &fromLength);

        if (length > 0) {
            char peerIP[INET_ADDRSTRLEN] = "?";
            cJSON *root;
            buffer[length] = '\0';
            inet_ntop(AF_INET, &from.sin_addr, peerIP, sizeof peerIP);
            root = cJSON_Parse(buffer);

            if (root != NULL) {
                cJSON *announce = cJSON_GetObjectItem(root, "announce");
                cJSON *fingerprintItem = cJSON_GetObjectItem(root, "fingerprint");
                cJSON *protocolItem = cJSON_GetObjectItem(root, "protocol");
                cJSON *portItem = cJSON_GetObjectItem(root, "port");
                cJSON *aliasItem = cJSON_GetObjectItem(root, "alias");
                cJSON *modelItem = cJSON_GetObjectItem(root, "deviceModel");
                cJSON *versionItem = cJSON_GetObjectItem(root, "version");
                cJSON *typeItem = cJSON_GetObjectItem(root, "deviceType");

                BOOL shouldAnswer = cJSON_IsTrue(announce);
                if (shouldAnswer && cJSON_IsString(fingerprintItem) &&
                    cJSON_IsString(protocolItem) &&
                    strcasecmp(protocolItem->valuestring, "https") == 0 &&
                    strcasecmp(fingerprintItem->valuestring, identity->fingerprint) != 0) {
                    int port = cJSON_IsNumber(portItem) ? (int)portItem->valuedouble : OS_PORT;
                    const char *fingerprint = fingerprintItem->valuestring;
                    time_t now = time(NULL);
                    int i;
                    BOOL recentlySeen = NO;

                    for (i = 0; i < 16; i++) {
                        if (cache[i].fingerprint[0] != '\0' &&
                            strcmp(cache[i].fingerprint, fingerprint) == 0) {
                            if (now - cache[i].lastSeen < 8) recentlySeen = YES;
                            break;
                        }
                    }

                    if (!recentlySeen) {
                        NSString *alias = cJSON_IsString(aliasItem) && aliasItem->valuestring != NULL
                                        ? [NSString stringWithUTF8String:aliasItem->valuestring]
                                        : NSLocalizedString(@"device.unknown", nil);
                        NSString *model = cJSON_IsString(modelItem) && modelItem->valuestring != NULL
                                        ? [NSString stringWithUTF8String:modelItem->valuestring]
                                        : @"";
                        NSString *version = cJSON_IsString(versionItem) && versionItem->valuestring != NULL
                                          ? [NSString stringWithUTF8String:versionItem->valuestring]
                                          : @"";
                        NSString *deviceType = cJSON_IsString(typeItem) && typeItem->valuestring != NULL
                                             ? [NSString stringWithUTF8String:typeItem->valuestring]
                                             : @"";
                        NSString *body = [NSString stringWithFormat:
                            @"{\"alias\":\"%@\",\"version\":\"%s\",\"deviceModel\":\"%@\",\"deviceType\":\"mobile\",\"fingerprint\":\"%@\",\"port\":%d,\"protocol\":\"https\",\"download\":false}",
                            os_json_escape(_alias), OS_PROTOCOL_VERSION,
                            os_json_escape(_model), _fingerprint, OS_PORT];
                        char status[128] = {0};
                        int result = os_register_peer(identity, &config, peerIP, port,
                                                      fingerprint, [body UTF8String],
                                                      status, sizeof status);
                        if (result == 0) {
                            NSDictionary *deviceInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                alias, @"alias",
                                [NSString stringWithUTF8String:peerIP], @"ip",
                                [NSNumber numberWithInt:port], @"port",
                                [NSString stringWithUTF8String:fingerprint], @"fingerprint",
                                model, @"model",
                                version, @"version",
                                deviceType, @"type",
                                @"https", @"protocol", nil];
                            [self performSelectorOnMainThread:@selector(addDeviceInfo:)
                                                   withObject:deviceInfo
                                                waitUntilDone:NO];
                            os_logf(self, @"Discovered %@ (%s)", alias, peerIP);
                        } else {
                            os_logf(self, @"Register reply failed (%d) %@ (%s)", result, alias, peerIP);
                        }

                        {
                            int slot = -1;
                            for (i = 0; i < 16; i++) {
                                if (cache[i].fingerprint[0] == '\0') {
                                    slot = i;
                                    break;
                                }
                            }
                            if (slot < 0) {
                                slot = 0;
                                for (i = 1; i < 16; i++) {
                                    if (cache[i].lastSeen < cache[slot].lastSeen) slot = i;
                                }
                            }
                            snprintf(cache[slot].fingerprint, sizeof cache[slot].fingerprint,
                                     "%s", fingerprint);
                            cache[slot].lastSeen = now;
                        }
                    }
                }
                cJSON_Delete(root);
            }
        }

        [pool release];
    }

    close(fd);
    mbedtls_ssl_config_free(&config);
    mbedtls_ctr_drbg_free(&drbg);
    mbedtls_entropy_free(&entropy);
    [outerPool release];
}

- (void)start {
    if (_running) return;

    {
        NSString *savedAlias = [[NSUserDefaults standardUserDefaults] stringForKey:@"device_alias"];
        if ([savedAlias length] == 0) {
            savedAlias = [OSServer generateAlias];
            [[NSUserDefaults standardUserDefaults] setObject:savedAlias forKey:@"device_alias"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        _alias = [savedAlias copy];
    }
    _model = [[[UIDevice currentDevice] model] copy];
    if ([_model length] == 0) {
        [_model release];
        _model = [@"iPod touch" copy];
    }
    _localIP = [[OSServer localIPAddress] copy];

    NSString *dir = @"/var/mobile/Library/OldSend";
    OSIdentity *identity = (OSIdentity *)calloc(1, sizeof(OSIdentity));
    char err[256] = {0};
    int ret = os_identity_init(identity, dir, err, sizeof err);
    if (ret != 0) {
        _status = [[NSString stringWithFormat:NSLocalizedString(@"status.cert_failed", nil), err] retain];
        os_identity_free(identity);
        [self appendLog:_status];
        [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification object:self];
        return;
    }

    _identity = identity;
    _fingerprint = [[NSString alloc] initWithUTF8String:identity->fingerprint];
    _status = [NSLocalizedString(@"status.ready", nil) retain];
    _running = YES;

    [NSThread detachNewThreadSelector:@selector(serverThreadMain)
                             toTarget:self
                           withObject:nil];
    [NSThread detachNewThreadSelector:@selector(discoveryThreadMain)
                             toTarget:self
                           withObject:nil];
    [NSThread detachNewThreadSelector:@selector(retryPendingPhotosThread)
                             toTarget:self
                           withObject:nil];

    [self announceNow];
    _announceTimer = [[NSTimer scheduledTimerWithTimeInterval:5.0
                                                      target:self
                                                    selector:@selector(announceTimerFired:)
                                                    userInfo:nil
                                                     repeats:YES] retain];

    [self appendLog:[NSString stringWithFormat:@"Started on port %d", OS_PORT]];
    [self appendLog:[NSString stringWithFormat:@"Fingerprint %@", _fingerprint]];
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidUpdateNotification object:self];
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    [_announceTimer invalidate];
    [_announceTimer release];
    _announceTimer = nil;
}

- (void)serverThreadMain {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self runServer];
    [pool release];
}

- (void)runServer {
    OSIdentity *identity = (OSIdentity *)_identity;
    mbedtls_ssl_config conf;
    int ret;

    mbedtls_ssl_config_init(&conf);
    ret = mbedtls_ssl_config_defaults(&conf, MBEDTLS_SSL_IS_SERVER,
                                      MBEDTLS_SSL_TRANSPORT_STREAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        os_logf(self, @"TLS config failed (%d)", ret);
        mbedtls_ssl_config_free(&conf);
        return;
    }

    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &identity->drbg);
    mbedtls_ssl_conf_min_version(&conf, MBEDTLS_SSL_MAJOR_VERSION_3,
                                 MBEDTLS_SSL_MINOR_VERSION_3);
    mbedtls_ssl_conf_max_version(&conf, MBEDTLS_SSL_MAJOR_VERSION_3,
                                 MBEDTLS_SSL_MINOR_VERSION_3);
    mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);

    ret = mbedtls_ssl_conf_own_cert(&conf, &identity->cert, &identity->key);
    if (ret != 0) {
        os_logf(self, @"Certificate load failed (%d)", ret);
        mbedtls_ssl_config_free(&conf);
        return;
    }

    int listenFD = socket(AF_INET, SOCK_STREAM, 0);
    if (listenFD < 0) {
        os_logf(self, @"socket() failed: %s", strerror(errno));
        mbedtls_ssl_config_free(&conf);
        return;
    }

    int one = 1;
    setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(OS_PORT);

    if (bind(listenFD, (struct sockaddr *)&addr, sizeof addr) != 0) {
        os_logf(self, @"Bind to port %d failed: %s", OS_PORT, strerror(errno));
        close(listenFD);
        mbedtls_ssl_config_free(&conf);
        return;
    }

    if (listen(listenFD, 8) != 0) {
        os_logf(self, @"listen() failed: %s", strerror(errno));
        close(listenFD);
        mbedtls_ssl_config_free(&conf);
        return;
    }

    os_logf(self, @"TLS server listening on %@:%d", _localIP, OS_PORT);

    while (_running) {
        struct sockaddr_in peer;
        socklen_t peerLen = sizeof peer;
        int clientFD = accept(listenFD, (struct sockaddr *)&peer, &peerLen);
        if (clientFD < 0) {
            if (errno == EINTR) continue;
            os_logf(self, @"accept() failed: %s", strerror(errno));
            break;
        }

        char peerIP[INET_ADDRSTRLEN] = "?";
        inet_ntop(AF_INET, &peer.sin_addr, peerIP, sizeof peerIP);

        [self handleClient:clientFD peer:peerIP config:&conf];
        close(clientFD);
    }

    close(listenFD);
    mbedtls_ssl_config_free(&conf);
    os_logf(self, @"TLS server stopped");
}

- (void)handleClient:(int)clientFD peer:(const char *)peer config:(mbedtls_ssl_config *)conf {
    mbedtls_ssl_context ssl;
    int one = 1;
    struct timeval tv;
    int ret;

    setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);

    mbedtls_ssl_init(&ssl);
    ret = mbedtls_ssl_setup(&ssl, conf);
    if (ret != 0) {
        os_logf(self, @"TLS init failed (%d)", ret);
        mbedtls_ssl_free(&ssl);
        return;
    }
    mbedtls_ssl_set_bio(&ssl, &clientFD, os_bio_send, os_bio_recv, NULL);

    ret = mbedtls_ssl_handshake(&ssl);
    if (ret != 0) {
        char text[128];
        os_mbed_error(text, sizeof text, ret);
        os_logf(self, @"TLS handshake failed (%s) from %s", text, peer);
        mbedtls_ssl_free(&ssl);
        return;
    }

    os_logf(self, @"TLS %s / %s ← %s",
            mbedtls_ssl_get_version(&ssl),
            mbedtls_ssl_get_ciphersuite(&ssl),
            peer);

    [self handleHTTP:&ssl peer:peer];

    mbedtls_ssl_close_notify(&ssl);
    mbedtls_ssl_free(&ssl);
}

- (void)sendResponse:(mbedtls_ssl_context *)ssl status:(int)status body:(NSString *)body {
    const char *reason;
    switch (status) {
        case 200: reason = "OK"; break;
        case 204: reason = "No Content"; break;
        case 400: reason = "Bad Request"; break;
        case 403: reason = "Forbidden"; break;
        case 404: reason = "Not Found"; break;
        case 409: reason = "Conflict"; break;
        case 422: reason = "Unprocessable Entity"; break;
        case 500: reason = "Internal Server Error"; break;
        default: reason = "Error"; break;
    }

    const char *bytes = body != nil ? [body UTF8String] : "";
    size_t length = strlen(bytes);
    char header[512];
    snprintf(header, sizeof header,
             "HTTP/1.1 %d %s\r\n"
             "Content-Type: application/json\r\n"
             "Content-Length: %lu\r\n"
             "Connection: close\r\n"
             "\r\n",
             status, reason, (unsigned long)length);

    if (os_ssl_write_all(ssl, header, strlen(header)) == 0 && length > 0) {
        os_ssl_write_all(ssl, bytes, length);
    }
}

- (void)addDeviceFromRegisterJSON:(const unsigned char *)body length:(size_t)length ip:(const char *)ip {
    cJSON *root = cJSON_Parse((const char *)body);
    if (root == NULL) return;

    {
        cJSON *aliasItem = cJSON_GetObjectItem(root, "alias");
        cJSON *fingerprintItem = cJSON_GetObjectItem(root, "fingerprint");
        cJSON *portItem = cJSON_GetObjectItem(root, "port");
        cJSON *modelItem = cJSON_GetObjectItem(root, "deviceModel");
        cJSON *protocolItem = cJSON_GetObjectItem(root, "protocol");
        cJSON *versionItem = cJSON_GetObjectItem(root, "version");
        cJSON *typeItem = cJSON_GetObjectItem(root, "deviceType");

        if (cJSON_IsString(fingerprintItem) && fingerprintItem->valuestring != NULL &&
            strcasecmp(fingerprintItem->valuestring, [_fingerprint UTF8String]) != 0) {
            NSString *alias = cJSON_IsString(aliasItem) && aliasItem->valuestring != NULL
                            ? [NSString stringWithUTF8String:aliasItem->valuestring]
                            : NSLocalizedString(@"device.unknown", nil);
            NSString *model = cJSON_IsString(modelItem) && modelItem->valuestring != NULL
                            ? [NSString stringWithUTF8String:modelItem->valuestring]
                            : @"";
            NSString *protocol = cJSON_IsString(protocolItem) && protocolItem->valuestring != NULL
                               ? [NSString stringWithUTF8String:protocolItem->valuestring]
                               : @"https";
            NSString *version = cJSON_IsString(versionItem) && versionItem->valuestring != NULL
                              ? [NSString stringWithUTF8String:versionItem->valuestring]
                              : @"";
            NSString *deviceType = cJSON_IsString(typeItem) && typeItem->valuestring != NULL
                                 ? [NSString stringWithUTF8String:typeItem->valuestring]
                                 : @"";
            NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                alias, @"alias",
                [NSString stringWithUTF8String:ip], @"ip",
                [NSNumber numberWithInt:(cJSON_IsNumber(portItem) ? (int)portItem->valuedouble : OS_PORT)], @"port",
                [NSString stringWithUTF8String:fingerprintItem->valuestring], @"fingerprint",
                model, @"model",
                protocol, @"protocol",
                version, @"version",
                deviceType, @"type", nil];
            [self performSelectorOnMainThread:@selector(addDeviceInfo:)
                                   withObject:info
                                waitUntilDone:NO];
        }
    }

    cJSON_Delete(root);
}

- (void)deliverSendResult:(NSDictionary *)result {
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerSendDidFinishNotification
                                                        object:self
                                                      userInfo:result];
}

- (void)deliverSendProgress:(NSNumber *)value {
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerSendProgressNotification
                                                        object:self
                                                      userInfo:[NSDictionary dictionaryWithObject:value
                                                                                           forKey:@"progress"]];
}

- (void)sendItems:(NSArray *)items toDevice:(NSDictionary *)device {
    NSDictionary *job;

    if (![NSThread isMainThread]) {
        NSArray *info = [NSArray arrayWithObjects:items, device, nil];
        [self performSelectorOnMainThread:@selector(sendInfo:)
                               withObject:info
                            waitUntilDone:NO];
        return;
    }
    if ([items count] == 0) return;

    gCancelSend = NO;
    gSendFD = -1;
    job = [NSDictionary dictionaryWithObjectsAndKeys:
           items, @"items", device, @"device", nil];
    [NSThread detachNewThreadSelector:@selector(sendThreadMain:)
                             toTarget:self
                           withObject:job];
}

- (void)sendInfo:(NSArray *)info {
    [self sendItems:[info objectAtIndex:0] toDevice:[info objectAtIndex:1]];
}

- (void)cancelSending {
    int fd;
    gCancelSend = YES;
    fd = gSendFD;
    gSendFD = -1;
    if (fd >= 0) {
        shutdown(fd, SHUT_RDWR);
    }
}

- (void)sendThreadMain:(NSDictionary *)job {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    OSIdentity *identity = (OSIdentity *)_identity;
    NSArray *items = [job objectForKey:@"items"];
    NSDictionary *device = [job objectForKey:@"device"];
    NSMutableArray *files = [NSMutableArray array];
    NSMutableArray *tempPaths = [NSMutableArray array];
    NSMutableDictionary *tokens = [NSMutableDictionary dictionary];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *outgoingDirectory = @"/var/mobile/Library/OldSend/Outgoing";
    NSString *errorMessage = nil;
    BOOL success = NO;
    BOOL cancelled = NO;
    NSString *sessionIdString = nil;
    long long totalBytes = 0;
    long long uploadedBase = 0;
    int status = 0;
    int result = 0;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_ssl_config config;
    OSSendProgressContext progressContext;
    const char *ip = [[device objectForKey:@"ip"] UTF8String];
    int port = [[device objectForKey:@"port"] intValue];
    const char *fingerprint = [[device objectForKey:@"fingerprint"] UTF8String];

    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&drbg);
    mbedtls_ssl_config_init(&config);
    progressContext.server = self;
    progressContext.base = 0;
    progressContext.total = 0;
    progressContext.lastReported = 0;

    if (identity == NULL || ip == NULL || port <= 0 || [items count] == 0) {
        errorMessage = NSLocalizedString(@"send.failed_message", nil);
        goto cleanup;
    }

    [manager createDirectoryAtPath:outgoingDirectory
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL];

    for (NSDictionary *item in items) {
        NSString *kind = [item objectForKey:@"kind"];
        char fileId[33];
        NSString *path;
        NSString *name;
        NSString *type;
        NSString *preview = @"";
        BOOL temporary = NO;
        long long size;

        os_make_id(fileId);

        if ([kind isEqualToString:@"media"] || [kind isEqualToString:@"file"]) {
            path = [item objectForKey:@"path"];
            name = [item objectForKey:@"name"];
            type = [item objectForKey:@"type"];
            if ([name length] == 0) name = [path lastPathComponent];
            if ([type length] == 0) type = @"application/octet-stream";
        } else {
            NSString *text = [item objectForKey:@"text"];
            if ([text length] == 0) continue;

            path = [outgoingDirectory stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"message-%s.txt", fileId]];
            if (![text writeToFile:path atomically:YES
                          encoding:NSUTF8StringEncoding error:NULL]) {
                errorMessage = NSLocalizedString(@"send.failed_message", nil);
                goto cleanup;
            }
            name = [NSString stringWithFormat:@"%s.txt", fileId];
            type = @"text/plain";
            preview = text;
            temporary = YES;
            [tempPaths addObject:path];
        }

        if ([path length] == 0 || ![manager fileExistsAtPath:path]) {
            errorMessage = NSLocalizedString(@"send.failed_message", nil);
            goto cleanup;
        }

        size = [[[manager attributesOfItemAtPath:path error:NULL]
                 objectForKey:NSFileSize] longLongValue];
        if (size <= 0) {
            errorMessage = NSLocalizedString(@"send.failed_message", nil);
            goto cleanup;
        }

        [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithUTF8String:fileId], @"id",
            path, @"path",
            name, @"name",
            type, @"type",
            [NSNumber numberWithLongLong:size], @"size",
            preview, @"preview",
            [NSNumber numberWithBool:temporary], @"temp", nil]];
        totalBytes += size;
    }

    if ([files count] == 0 || totalBytes <= 0) {
        errorMessage = NSLocalizedString(@"send.failed_message", nil);
        goto cleanup;
    }

    {
        static const unsigned char personalization[] = "oldsend-send";
        int ret = mbedtls_ctr_drbg_seed(&drbg, mbedtls_entropy_func, &entropy,
                                        personalization, sizeof personalization - 1);
        if (ret == 0) {
            ret = mbedtls_ssl_config_defaults(&config, MBEDTLS_SSL_IS_CLIENT,
                                              MBEDTLS_SSL_TRANSPORT_STREAM,
                                              MBEDTLS_SSL_PRESET_DEFAULT);
        }
        if (ret == 0) {
            mbedtls_ssl_conf_rng(&config, mbedtls_ctr_drbg_random, &drbg);
            mbedtls_ssl_conf_min_version(&config, MBEDTLS_SSL_MAJOR_VERSION_3,
                                         MBEDTLS_SSL_MINOR_VERSION_3);
            mbedtls_ssl_conf_max_version(&config, MBEDTLS_SSL_MAJOR_VERSION_3,
                                         MBEDTLS_SSL_MINOR_VERSION_3);
            mbedtls_ssl_conf_authmode(&config, MBEDTLS_SSL_VERIFY_NONE);
            ret = mbedtls_ssl_conf_own_cert(&config, &identity->cert, &identity->key);
        }
        if (ret != 0) {
            errorMessage = NSLocalizedString(@"send.failed_message", nil);
            goto cleanup;
        }
    }

    {
        cJSON *root = cJSON_CreateObject();
        cJSON *info = cJSON_AddObjectToObject(root, "info");
        cJSON *filesObject = cJSON_AddObjectToObject(root, "files");
        char *json;
        NSMutableData *response = [NSMutableData data];

        cJSON_AddStringToObject(info, "alias", [_alias UTF8String]);
        cJSON_AddStringToObject(info, "version", OS_PROTOCOL_VERSION);
        cJSON_AddStringToObject(info, "deviceModel", [_model UTF8String]);
        cJSON_AddStringToObject(info, "deviceType", "mobile");
        cJSON_AddStringToObject(info, "fingerprint", [_fingerprint UTF8String]);
        cJSON_AddNumberToObject(info, "port", OS_PORT);
        cJSON_AddStringToObject(info, "protocol", "https");
        cJSON_AddBoolToObject(info, "download", 0);

        for (NSDictionary *file in files) {
            const char *fileId = [[file objectForKey:@"id"] UTF8String];
            cJSON *entry = cJSON_AddObjectToObject(filesObject, fileId);
            NSString *preview = [file objectForKey:@"preview"];

            cJSON_AddStringToObject(entry, "id", fileId);
            cJSON_AddStringToObject(entry, "fileName", [[file objectForKey:@"name"] UTF8String]);
            cJSON_AddNumberToObject(entry, "size",
                                    (double)[[file objectForKey:@"size"] longLongValue]);
            cJSON_AddStringToObject(entry, "fileType", [[file objectForKey:@"type"] UTF8String]);
            if ([preview length] > 0) {
                cJSON_AddStringToObject(entry, "preview", [preview UTF8String]);
            }
        }

        json = cJSON_PrintUnformatted(root);
        result = os_client_request(identity, &config, ip, port, fingerprint,
                                   "/api/localsend/v2/prepare-upload",
                                   "application/json", json, strlen(json),
                                   NULL, 0, response, &status, NULL, NULL);
        gSendFD = -1;
        free(json);
        cJSON_Delete(root);

        if (gCancelSend) {
            cancelled = YES;
            goto cleanup;
        }
        if (result != 0 || status != 200) {
            os_logf(self, @"Send prepare failed (rc=%d, status=%d)", result, status);
            errorMessage = NSLocalizedString(@"send.failed_message", nil);
            goto cleanup;
        }

        [response appendBytes:"\0" length:1];
        {
            cJSON *responseRoot = cJSON_Parse([response bytes]);
            cJSON *sessionItem = responseRoot != NULL ? cJSON_GetObjectItem(responseRoot, "sessionId") : NULL;
            cJSON *filesItem = responseRoot != NULL ? cJSON_GetObjectItem(responseRoot, "files") : NULL;

            if (!cJSON_IsString(sessionItem) || filesItem == NULL) {
                if (responseRoot != NULL) cJSON_Delete(responseRoot);
                errorMessage = NSLocalizedString(@"send.failed_message", nil);
                goto cleanup;
            }

            for (NSDictionary *file in files) {
                NSString *fileId = [file objectForKey:@"id"];
                cJSON *tokenItem = cJSON_GetObjectItem(filesItem, [fileId UTF8String]);
                if (!cJSON_IsString(tokenItem) || tokenItem->valuestring == NULL) {
                    cJSON_Delete(responseRoot);
                    errorMessage = NSLocalizedString(@"send.failed_message", nil);
                    goto cleanup;
                }
                [tokens setObject:[NSString stringWithUTF8String:tokenItem->valuestring]
                           forKey:fileId];
            }

            sessionIdString = [[NSString stringWithUTF8String:sessionItem->valuestring] copy];
            progressContext.total = totalBytes;

            if (gCancelSend) {
                cancelled = YES;
                cJSON_Delete(responseRoot);
                goto cleanup;
            }

            for (NSDictionary *file in files) {
                NSString *fileId = [file objectForKey:@"id"];
                NSString *token = [tokens objectForKey:fileId];
                long long size = [[file objectForKey:@"size"] longLongValue];
                char uploadPath[1024];

                snprintf(uploadPath, sizeof uploadPath,
                         "/api/localsend/v2/upload?sessionId=%s&fileId=%s&token=%s",
                         sessionItem->valuestring, [fileId UTF8String], [token UTF8String]);
                progressContext.base = uploadedBase;
                progressContext.lastReported = uploadedBase;

                result = os_client_request(identity, &config, ip, port, fingerprint,
                                           uploadPath, "application/octet-stream",
                                           NULL, 0,
                                           [[file objectForKey:@"path"] fileSystemRepresentation],
                                           size, nil, &status,
                                           os_send_progress_cb, &progressContext);
                if (gCancelSend) {
                    cancelled = YES;
                    cJSON_Delete(responseRoot);
                    goto cleanup;
                }
                if (result != 0 || status != 200) {
                    os_logf(self, @"Send upload failed (rc=%d, status=%d)", result, status);
                    cJSON_Delete(responseRoot);
                    errorMessage = NSLocalizedString(@"send.failed_message", nil);
                    goto cleanup;
                }
                uploadedBase += size;
            }

            cJSON_Delete(responseRoot);
        }

        os_logf(self, @"Sent %d file(s) to %@", (int)[files count],
                [device objectForKey:@"alias"]);
        [self performSelectorOnMainThread:@selector(deliverSendProgress:)
                               withObject:[NSNumber numberWithFloat:1.0f]
                            waitUntilDone:NO];
        success = YES;
    }

cleanup:
    if (cancelled && sessionIdString != nil) {
        char cancelPath[512];
        gCancelSend = NO;
        snprintf(cancelPath, sizeof cancelPath,
                 "/api/localsend/v2/cancel?sessionId=%s",
                 [sessionIdString UTF8String]);
        os_client_request(identity, &config, ip, port, fingerprint,
                          cancelPath, "application/json", "", 0,
                          NULL, 0, nil, &status, NULL, NULL);
        gSendFD = -1;
    }
    [sessionIdString release];
    for (NSString *temporaryPath in tempPaths) {
        [[NSFileManager defaultManager] removeItemAtPath:temporaryPath error:NULL];
    }
    mbedtls_ssl_config_free(&config);
    mbedtls_ctr_drbg_free(&drbg);
    mbedtls_entropy_free(&entropy);

    {
        NSDictionary *resultInfo = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:success], @"success",
            [NSNumber numberWithBool:cancelled], @"cancelled",
            errorMessage != nil ? errorMessage : @"", @"message",
            [device objectForKey:@"alias"], @"alias", nil];
        [self performSelectorOnMainThread:@selector(deliverSendResult:)
                               withObject:resultInfo
                            waitUntilDone:NO];
    }

    [pool release];
}

- (void)showDecisionAlert:(NSArray *)info {
    NSString *title = [info objectAtIndex:0];
    NSString *message = [info objectAtIndex:1];

    _decisionAlert = [[UIAlertView alloc] initWithTitle:title
                                                 message:message
                                                delegate:self
                                       cancelButtonTitle:NSLocalizedString(@"common.decline", nil)
                                       otherButtonTitles:NSLocalizedString(@"common.accept", nil), nil];
    [_decisionAlert show];
}

- (void)dismissDecisionAlert {
    UIAlertView *alert = _decisionAlert;
    _decisionAlert = nil;
    if (alert != nil) {
        [alert dismissWithClickedButtonIndex:0 animated:NO];
        [alert release];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    [_decisionCondition lock];
    _decisionAccepted = (buttonIndex != alertView.cancelButtonIndex);
    _decisionMade = YES;
    [_decisionCondition broadcast];
    [_decisionCondition unlock];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView == _decisionAlert) {
        [_decisionAlert release];
        _decisionAlert = nil;
    }
}

- (BOOL)askToAcceptWithTitle:(NSString *)title message:(NSString *)message {
    NSArray *info;
    BOOL accepted;

    [_decisionCondition lock];
    _decisionMade = NO;
    _decisionAccepted = NO;
    [_decisionCondition unlock];

    info = [NSArray arrayWithObjects:title,
            message != nil ? message : @"", nil];
    [self performSelectorOnMainThread:@selector(showDecisionAlert:)
                           withObject:info
                        waitUntilDone:NO];

    [_decisionCondition lock];
    {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
        while (!_decisionMade && [deadline timeIntervalSinceNow] > 0) {
            [_decisionCondition waitUntilDate:deadline];
        }
        accepted = _decisionMade && _decisionAccepted;
        if (!_decisionMade) {
            [self performSelectorOnMainThread:@selector(dismissDecisionAlert)
                                   withObject:nil
                                waitUntilDone:NO];
        }
    }
    [_decisionCondition unlock];
    return accepted;
}

- (int)handlePrepare:(const unsigned char *)body length:(size_t)length response:(NSString **)response {
    cJSON *root;
    cJSON *files;
    cJSON *child;
    cJSON *infoItem;
    cJSON *aliasItem;
    cJSON *responseRoot;
    cJSON *responseFiles;
    OSSession session;
    OSIdentity *identity = (OSIdentity *)_identity;
    NSMutableString *summary;
    NSString *sender;
    NSString *title;
    NSString *message;
    BOOL textOnly = YES;
    BOOL accepted = NO;
    BOOL quickSave = [[NSUserDefaults standardUserDefaults] boolForKey:@"quick_save"];
    int images = 0, videos = 0, audio = 0, textFiles = 0, other = 0;
    int i;

    *response = nil;
    root = cJSON_Parse((const char *)body);
    if (root == NULL) return 400;

    files = cJSON_GetObjectItem(root, "files");
    if (!cJSON_IsObject(files)) {
        cJSON_Delete(root);
        return 400;
    }

    if (gSession.active) {
        cJSON_Delete(root);
        return 409;
    }

    memset(&session, 0, sizeof session);
    for (child = files->child; child != NULL && session.count < OS_MAX_FILES; child = child->next) {
        cJSON *nameItem;
        cJSON *sizeItem;
        cJSON *shaItem;
        cJSON *typeItem;
        cJSON *previewItem;
        OSFileEntry *entry;

        if (!cJSON_IsObject(child) || child->string == NULL) continue;
        nameItem = cJSON_GetObjectItem(child, "fileName");
        if (!cJSON_IsString(nameItem) || nameItem->valuestring == NULL) continue;

        entry = &session.files[session.count];
        snprintf(entry->id, sizeof entry->id, "%s", child->string);
        os_sanitize_filename(nameItem->valuestring, entry->name, sizeof entry->name);

        sizeItem = cJSON_GetObjectItem(child, "size");
        entry->size = cJSON_IsNumber(sizeItem) ? (long long)sizeItem->valuedouble : 0;

        shaItem = cJSON_GetObjectItem(child, "sha256");
        if (cJSON_IsString(shaItem) && shaItem->valuestring != NULL) {
            snprintf(entry->sha256, sizeof entry->sha256, "%s", shaItem->valuestring);
        }

        typeItem = cJSON_GetObjectItem(child, "fileType");
        if (cJSON_IsString(typeItem) && typeItem->valuestring != NULL) {
            snprintf(entry->type, sizeof entry->type, "%s", typeItem->valuestring);
        }

        /* LocalSend puts the full text of a text/clipboard message into the
           optional preview field. A normal .txt file selected by the user has
           no preview, which is how the two are told apart. */
        previewItem = cJSON_GetObjectItem(child, "preview");
        entry->isMessage = (strncmp(entry->type, "text/", 5) == 0 &&
                            cJSON_IsString(previewItem) &&
                            previewItem->valuestring != NULL);
        if (!entry->isMessage) {
            textOnly = NO;
        }
        if (strncmp(entry->type, "image/", 6) == 0) {
            images++;
        } else if (strncmp(entry->type, "video/", 6) == 0) {
            videos++;
        } else if (strncmp(entry->type, "audio/", 6) == 0) {
            audio++;
        } else if (strncmp(entry->type, "text/", 5) == 0) {
            textFiles++;
        } else {
            other++;
        }
        session.count++;
    }

    if (session.count == 0) {
        cJSON_Delete(root);
        return 204;
    }

    infoItem = cJSON_GetObjectItem(root, "info");
    aliasItem = infoItem != NULL ? cJSON_GetObjectItem(infoItem, "alias") : NULL;
    sender = cJSON_IsString(aliasItem) && aliasItem->valuestring != NULL
           ? [NSString stringWithUTF8String:aliasItem->valuestring]
           : NSLocalizedString(@"device.unknown", nil);

    if (textOnly) {
        title = NSLocalizedString(@"receive.text_title", nil);
        message = [NSString stringWithFormat:NSLocalizedString(@"receive.text_message", nil),
                   sender];
    } else {
        title = NSLocalizedString(@"receive.file_title", nil);

        if (session.count <= 3) {
            summary = [NSMutableString string];
            for (i = 0; i < session.count; i++) {
                if (i > 0) [summary appendString:@"\n"];
                [summary appendString:[NSString stringWithUTF8String:session.files[i].name]];
            }
            message = [NSString stringWithFormat:NSLocalizedString(@"receive.file_message", nil),
                       sender, session.count, summary];
        } else {
            NSMutableArray *parts = [NSMutableArray array];
            NSString *typeSummary;

            if (images > 0) {
                [parts addObject:[NSString stringWithFormat:
                                  NSLocalizedString(@"receive.count_images", nil), images]];
            }
            if (videos > 0) {
                [parts addObject:[NSString stringWithFormat:
                                  NSLocalizedString(@"receive.count_videos", nil), videos]];
            }
            if (audio > 0) {
                [parts addObject:[NSString stringWithFormat:
                                  NSLocalizedString(@"receive.count_audio", nil), audio]];
            }
            if (textFiles > 0) {
                [parts addObject:[NSString stringWithFormat:
                                  NSLocalizedString(@"receive.count_text", nil), textFiles]];
            }
            if (other > 0) {
                [parts addObject:[NSString stringWithFormat:
                                  NSLocalizedString(@"receive.count_other", nil), other]];
            }
            typeSummary = [parts componentsJoinedByString:
                           NSLocalizedString(@"common.list_separator", nil)];

            if (images == session.count) {
                message = [NSString stringWithFormat:
                           NSLocalizedString(@"receive.many_images", nil),
                           sender, session.count];
            } else if (videos == session.count) {
                message = [NSString stringWithFormat:
                           NSLocalizedString(@"receive.many_videos", nil),
                           sender, session.count];
            } else {
                message = [NSString stringWithFormat:
                           NSLocalizedString(@"receive.file_message_many", nil),
                           sender, session.count, typeSummary];
            }
        }
    }

    /* Reserve the single session slot while the user decides. */
    gSession.active = 1;
    gSession.count = 0;
    gSession.remaining = 0;

    if (quickSave) {
        accepted = YES;
    } else {
        [self performSelectorOnMainThread:@selector(setReceiveStatusText:)
                               withObject:NSLocalizedString(@"status.preparing", nil)
                            waitUntilDone:NO];
        accepted = [self askToAcceptWithTitle:title message:message];
    }

    if (!accepted) {
        gSession.active = 0;
        cJSON_Delete(root);
        [self performSelectorOnMainThread:@selector(setReceiveStatusText:)
                               withObject:NSLocalizedString(@"status.waiting", nil)
                            waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(setSessionActiveFlag:)
                               withObject:[NSNumber numberWithBool:NO]
                            waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(resetReceivedTexts)
                               withObject:nil
                            waitUntilDone:NO];
        os_logf(self, @"Receiver declined the session from %@", sender);
        return 403;
    }

    [self performSelectorOnMainThread:@selector(resetReceivedTexts)
                           withObject:nil
                        waitUntilDone:NO];
    {
        long long totalBytes = 0;
        for (i = 0; i < session.count; i++) {
            if (session.files[i].size > 0) {
                totalBytes += session.files[i].size;
            }
        }
        [self performSelectorOnMainThread:@selector(beginSessionProgressWithTotal:)
                               withObject:[NSNumber numberWithLongLong:totalBytes]
                            waitUntilDone:NO];
    }
    [self performSelectorOnMainThread:@selector(setReceiveStatusText:)
                           withObject:NSLocalizedString(@"status.accepted", nil)
                        waitUntilDone:NO];
    os_random_hex(identity, session.sessionId, 16);
    snprintf(gLastSessionId, sizeof gLastSessionId, "%s", session.sessionId);
    session.active = 1;
    session.remaining = session.count;

    responseRoot = cJSON_CreateObject();
    cJSON_AddStringToObject(responseRoot, "sessionId", session.sessionId);
    responseFiles = cJSON_AddObjectToObject(responseRoot, "files");
    for (i = 0; i < session.count; i++) {
        os_random_hex(identity, session.files[i].token, 16);
        cJSON_AddStringToObject(responseFiles, session.files[i].id, session.files[i].token);
    }

    gSession = session;

    {
        char *printed = cJSON_PrintUnformatted(responseRoot);
        if (printed != NULL) {
            *response = [NSString stringWithUTF8String:printed];
            free(printed);
        }
    }
    cJSON_Delete(responseRoot);
    cJSON_Delete(root);

    os_logf(self, @"Preparing to receive %d file(s)", session.count);
    for (i = 0; i < session.count; i++) {
        os_logf(self, @"  %s (%lld bytes)", session.files[i].name, session.files[i].size);
    }
    return 200;
}

- (int)handleUpload:(mbedtls_ssl_context *)ssl request:(OSRequest *)request identity:(OSIdentity *)identity {
    char sessionId[64];
    char fileId[128];
    char token[64];
    OSFileEntry *entry = NULL;
    BOOL isTextEntry = NO;
    int i;
    NSString *directory = @OS_RECEIVED_DIR;
    NSString *tempDirectory;
    NSString *tempPath;
    NSString *finalPath;
    FILE *file;
    mbedtls_sha256_context sha;
    long long written = 0;
    unsigned char digest[32];
    char digestHex[65];

    if (!os_query_value(request->path, "sessionId", sessionId, sizeof sessionId) ||
        !os_query_value(request->path, "fileId", fileId, sizeof fileId) ||
        !os_query_value(request->path, "token", token, sizeof token)) {
        return 400;
    }
    if (!gSession.active || strcmp(sessionId, gSession.sessionId) != 0) return 403;

    for (i = 0; i < gSession.count; i++) {
        if (strcmp(gSession.files[i].id, fileId) == 0) {
            entry = &gSession.files[i];
            break;
        }
    }
    if (entry == NULL || strcmp(entry->token, token) != 0) return 403;
    if (entry->uploaded) return 409;
    isTextEntry = strncmp(entry->type, "text/", 5) == 0;

    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    tempDirectory = [directory stringByAppendingPathComponent:@".tmp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    tempPath = [tempDirectory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%s-%d.part", gSession.sessionId, i]];
    file = fopen([tempPath fileSystemRepresentation], "wb");
    if (file == NULL) {
        gSession.active = 0;
        gSession.remaining = 0;
        [self performSelectorOnMainThread:@selector(failReceivingFile)
                               withObject:nil
                            waitUntilDone:NO];
        return 500;
    }

    mbedtls_sha256_init(&sha);
    mbedtls_sha256_starts_ret(&sha, 0);

    {
        OSProgressContext progress;
        progress.server = self;
        progress.lastReported = 0;
        [self performSelectorOnMainThread:@selector(beginReceivingFile:)
                               withObject:[NSString stringWithUTF8String:entry->name]
                            waitUntilDone:NO];
        if (os_stream_body(ssl, request, file, &sha, &written,
                           entry->size > 0 ? entry->size : request->contentLength,
                           os_progress_cb, &progress) != 0) {
            fclose(file);
            unlink([tempPath fileSystemRepresentation]);
            mbedtls_sha256_free(&sha);
            gSession.active = 0;
            gSession.remaining = 0;
            [self performSelectorOnMainThread:@selector(failReceivingFile)
                                   withObject:nil
                                waitUntilDone:NO];
            os_logf(self, @"Upload interrupted: %s", entry->name);
            return 400;
        }
    }
    fclose(file);
    if (isTextEntry && entry->isMessage) {
        [self performSelectorOnMainThread:@selector(finishReceivingText)
                               withObject:nil
                            waitUntilDone:NO];
    } else {
        [self performSelectorOnMainThread:@selector(finishReceivingFile)
                               withObject:nil
                            waitUntilDone:NO];
    }

    mbedtls_sha256_finish_ret(&sha, digest);
    mbedtls_sha256_free(&sha);
    for (i = 0; i < 32; i++) {
        sprintf(digestHex + i * 2, "%02x", digest[i]);
    }
    digestHex[64] = '\0';

    if (entry->size > 0 && written != entry->size) {
        unlink([tempPath fileSystemRepresentation]);
        gSession.active = 0;
        gSession.remaining = 0;
        [self performSelectorOnMainThread:@selector(failReceivingFile)
                               withObject:nil
                            waitUntilDone:NO];
        os_logf(self, @"Size mismatch: %s (%lld / %lld)", entry->name, written, entry->size);
        return 400;
    }

    if (entry->sha256[0] != '\0' && strcasecmp(digestHex, entry->sha256) != 0) {
        unlink([tempPath fileSystemRepresentation]);
        gSession.active = 0;
        gSession.remaining = 0;
        [self performSelectorOnMainThread:@selector(failReceivingFile)
                               withObject:nil
                            waitUntilDone:NO];
        os_logf(self, @"Checksum mismatch: %s", entry->name);
        return 422;
    }

    if (isTextEntry) {
        if (entry->isMessage) {
            NSData *data = [NSData dataWithContentsOfFile:tempPath];
            NSString *content = nil;

            if (data != nil) {
                content = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
                if (content == nil) {
                    content = [[[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding] autorelease];
                }
            }
            if ([content length] > 0) {
                [self performSelectorOnMainThread:@selector(addReceivedText:)
                                       withObject:content
                                    waitUntilDone:NO];
            }
            unlink([tempPath fileSystemRepresentation]);
            entry->uploaded = 1;
            entry->path[0] = '\0';
            gSession.remaining--;
            os_logf(self, @"Received text message %s (%lld bytes)", entry->name, written);
        } else {
            finalPath = os_unique_path(directory, [NSString stringWithUTF8String:entry->name]);
            if (![[NSFileManager defaultManager] moveItemAtPath:tempPath
                                                         toPath:finalPath
                                                          error:NULL]) {
                unlink([tempPath fileSystemRepresentation]);
                gSession.active = 0;
                gSession.remaining = 0;
                [self performSelectorOnMainThread:@selector(failReceivingFile)
                                       withObject:nil
                                    waitUntilDone:NO];
                return 500;
            }
            entry->uploaded = 1;
            snprintf(entry->path, sizeof entry->path, "%s", [finalPath fileSystemRepresentation]);
            gSession.remaining--;
            os_logf(self, @"Received text file %s (%lld bytes) -> %@",
                    entry->name, written, [finalPath lastPathComponent]);
        }
    } else {
        finalPath = os_unique_path(directory, [NSString stringWithUTF8String:entry->name]);
        if (![[NSFileManager defaultManager] moveItemAtPath:tempPath
                                                     toPath:finalPath
                                                      error:NULL]) {
            unlink([tempPath fileSystemRepresentation]);
            gSession.active = 0;
            gSession.remaining = 0;
            [self performSelectorOnMainThread:@selector(failReceivingFile)
                                   withObject:nil
                                waitUntilDone:NO];
            return 500;
        }

        entry->uploaded = 1;
        snprintf(entry->path, sizeof entry->path, "%s", [finalPath fileSystemRepresentation]);
        gSession.remaining--;
        os_logf(self, @"Received %s (%lld bytes) -> %@",
                entry->name, written, [finalPath lastPathComponent]);
    }

    if (gSession.remaining <= 0) {
        NSMutableArray *photos = [NSMutableArray array];
        int receivedFileCount = 0;
        int j;

        for (j = 0; j < gSession.count; j++) {
            OSFileEntry *item = &gSession.files[j];
            NSString *extension;

            if (!item->uploaded || item->path[0] == '\0') continue;
            receivedFileCount++;
            extension = [[[NSString stringWithUTF8String:item->path] pathExtension] lowercaseString];

            if (strncmp(item->type, "image/", 6) == 0 ||
                strncmp(item->type, "video/", 6) == 0 ||
                [extension isEqualToString:@"jpg"] ||
                [extension isEqualToString:@"jpeg"] ||
                [extension isEqualToString:@"png"] ||
                [extension isEqualToString:@"mp4"] ||
                [extension isEqualToString:@"mov"] ||
                [extension isEqualToString:@"m4v"]) {
                [photos addObject:[NSArray arrayWithObjects:
                                   [NSString stringWithUTF8String:item->path],
                                   [NSString stringWithUTF8String:item->type], nil]];
            } else {
                os_logf(self, @"Kept in app: %s", item->name);
            }
        }

        gSession.active = 0;
        [self performSelectorOnMainThread:@selector(setSessionActiveFlag:)
                               withObject:[NSNumber numberWithBool:NO]
                            waitUntilDone:NO];
        os_logf(self, @"Session complete");

        if ([photos count] > 0) {
            [self performSelectorOnMainThread:@selector(enqueuePhotoBatch:)
                                   withObject:photos
                                waitUntilDone:NO];
        }
        [self performSelectorOnMainThread:@selector(showReceivedTexts)
                               withObject:nil
                            waitUntilDone:NO];
        if (receivedFileCount > 0) {
            [self performSelectorOnMainThread:@selector(queueReceiveCompleteAlert:)
                                   withObject:[NSNumber numberWithInt:receivedFileCount]
                                waitUntilDone:NO];
        }
    }
    return 200;
}

- (void)photo:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    NSUInteger token;
    NSString *path;

    [_photoCondition lock];
    token = _photoActiveToken;
    path = [[_photoActivePath retain] autorelease];
    if (token == _photoSaveToken) {
        _photoFinished = YES;
        _photoSuccess = (error == nil);
    }
    [_photoCondition broadcast];
    [_photoCondition unlock];

    if (error != nil) {
        os_logf(self, @"Photo save failed: %@", [error localizedDescription]);
    } else {
        os_logf(self, @"Saved to Photos");
    }

    {
        NSArray *result = [NSArray arrayWithObjects:
                           [NSNumber numberWithBool:(error == nil)],
                           path != nil ? path : @"",
                           [NSNumber numberWithUnsignedInteger:token], nil];
        [self performSelectorOnMainThread:@selector(photoSaveDidFinish:)
                               withObject:result
                            waitUntilDone:NO];
    }
}

- (void)photoSaveDidFinish:(NSArray *)result {
    BOOL success = [[result objectAtIndex:0] boolValue];
    NSString *path = [result objectAtIndex:1];

    if (success && [path length] > 0) {
        [self writeSavedMarkerForPath:path];
    }

    if (_photoQueueRunning) {
        [self saveNextPhoto];
    } else {
        if (_savingCount > 0) _savingCount--;
        [self updateSavingStatus];
        [self showPendingReceiveCompleteAlert];
    }
}

- (void)saveNextPhoto {
    NSArray *info;
    NSArray *payload;

    if ([_photoQueue count] == 0) {
        _photoQueueRunning = NO;
        _savingCount = 0;
        [self updateSavingStatus];
        [self showPendingReceiveCompleteAlert];
        return;
    }

    info = [[_photoQueue objectAtIndex:0] retain];
    [_photoQueue removeObjectAtIndex:0];

    _photoSaveToken++;
    _photoActiveToken = _photoSaveToken;
    [_photoActivePath release];
    _photoActivePath = [[info objectAtIndex:0] copy];

    payload = [NSArray arrayWithObjects:
               [info objectAtIndex:0],
               [info objectAtIndex:1],
               [NSNumber numberWithUnsignedInteger:_photoActiveToken], nil];
    [info release];

    [self beginSaveToPhotos:payload];
}

- (void)enqueuePhotoBatch:(NSArray *)items {
    BOOL added = NO;

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(enqueuePhotoBatch:)
                               withObject:items
                            waitUntilDone:NO];
        return;
    }

    if (_photoQueue == nil) {
        _photoQueue = [[NSMutableArray alloc] init];
    }

    for (NSArray *info in items) {
        NSString *path = [info objectAtIndex:0];
        NSString *type = [info objectAtIndex:1];
        NSString *extension = [[path pathExtension] lowercaseString];
        NSString *lowerType = [type lowercaseString];

        if ([lowerType hasPrefix:@"image/"] ||
            [lowerType hasPrefix:@"video/"] ||
            [extension isEqualToString:@"jpg"] ||
            [extension isEqualToString:@"jpeg"] ||
            [extension isEqualToString:@"png"] ||
            [extension isEqualToString:@"mp4"] ||
            [extension isEqualToString:@"mov"] ||
            [extension isEqualToString:@"m4v"]) {
            [_photoQueue addObject:info];
            added = YES;
        }
    }

    if (added && !_photoQueueRunning) {
        _photoQueueRunning = YES;
        _savingCount = 1;
        [self updateSavingStatus];
        [self saveNextPhoto];
    }
}

- (void)beginSaveToPhotos:(NSArray *)info {
    NSString *path = [info objectAtIndex:0];
    NSString *type = [info objectAtIndex:1];
    NSUInteger token = [[info objectAtIndex:2] unsignedIntegerValue];
    NSString *extension = [[path pathExtension] lowercaseString];
    NSString *lowerType = [type lowercaseString];

    if (token != _photoSaveToken) return;

    BOOL isImage = [lowerType hasPrefix:@"image/"] ||
                   [extension isEqualToString:@"jpg"] ||
                   [extension isEqualToString:@"jpeg"] ||
                   [extension isEqualToString:@"png"];
    BOOL isVideo = [lowerType hasPrefix:@"video/"] ||
                   [extension isEqualToString:@"mp4"] ||
                   [extension isEqualToString:@"mov"] ||
                   [extension isEqualToString:@"m4v"];

    if (isImage) {
        UIImage *image = [[UIImage alloc] initWithContentsOfFile:path];
        if (image == nil) {
            [_photoCondition lock];
            if (token == _photoSaveToken) {
                _photoFinished = YES;
                _photoSuccess = NO;
            }
            [_photoCondition broadcast];
            [_photoCondition unlock];
            os_logf(self, @"Image decode failed: %@", [path lastPathComponent]);
            if (_photoQueueRunning) {
                [self saveNextPhoto];
            }
            return;
        }
        os_logf(self, @"Saving image to Photos: %@", [path lastPathComponent]);
        UIImageWriteToSavedPhotosAlbum(image, self,
                                       @selector(photo:didFinishSavingWithError:contextInfo:),
                                       NULL);
        [image release];
    } else if (isVideo) {
        os_logf(self, @"Saving video to Photos: %@", [path lastPathComponent]);
        UISaveVideoAtPathToSavedPhotosAlbum(path, self,
                                            @selector(photo:didFinishSavingWithError:contextInfo:),
                                            NULL);
    } else {
        [_photoCondition lock];
        if (token == _photoSaveToken) {
            _photoFinished = YES;
            _photoSuccess = YES;
        }
        [_photoCondition broadcast];
        [_photoCondition unlock];
        os_logf(self, @"Kept in app: %@", [path lastPathComponent]);
        if (_photoQueueRunning) {
            [self saveNextPhoto];
        }
    }
}

- (BOOL)saveToPhotos:(NSString *)path type:(NSString *)type timeout:(NSTimeInterval)timeout {
    NSString *extension = [[path pathExtension] lowercaseString];
    NSString *lowerType = [type lowercaseString];
    BOOL isImage = [lowerType hasPrefix:@"image/"] ||
                   [extension isEqualToString:@"jpg"] ||
                   [extension isEqualToString:@"jpeg"] ||
                   [extension isEqualToString:@"png"];
    BOOL isVideo = [lowerType hasPrefix:@"video/"] ||
                   [extension isEqualToString:@"mp4"] ||
                   [extension isEqualToString:@"mov"] ||
                   [extension isEqualToString:@"m4v"];

    if (!isImage && !isVideo) {
        os_logf(self, @"Kept in app: %@", [path lastPathComponent]);
        return YES;
    }

    [_photoCondition lock];
    while (_photoSaveInProgress) {
        [_photoCondition wait];
    }
    _photoSaveInProgress = YES;
    _photoFinished = NO;
    _photoSuccess = NO;
    _photoSaveToken++;
    _photoActiveToken = _photoSaveToken;
    [_photoActivePath release];
    _photoActivePath = [path copy];
    [_photoCondition unlock];

    {
        NSArray *info = [NSArray arrayWithObjects:path, type,
                         [NSNumber numberWithUnsignedInteger:_photoActiveToken], nil];
        [self performSelectorOnMainThread:@selector(beginSaveToPhotos:)
                               withObject:info
                            waitUntilDone:NO];
    }

    [_photoCondition lock];
    {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        while (!_photoFinished && [deadline timeIntervalSinceNow] > 0) {
            [_photoCondition waitUntilDate:deadline];
        }
    }
    BOOL success = _photoFinished && _photoSuccess;
    if (!_photoFinished) {
        _photoSaveToken++;
        os_logf(self, @"Photo save timed out: %@", [path lastPathComponent]);
    }
    _photoSaveInProgress = NO;
    [_photoCondition broadcast];
    [_photoCondition unlock];
    return success;
}

- (void)writeSavedMarkerForPath:(NSString *)path {
    NSString *directory = [@OS_RECEIVED_DIR stringByAppendingPathComponent:@".saved"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [@"" writeToFile:[directory stringByAppendingPathComponent:[path lastPathComponent]]
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:NULL];
}

- (void)retryPendingPhotosThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = @OS_RECEIVED_DIR;
    NSString *markerDirectory = [directory stringByAppendingPathComponent:@".saved"];
    NSArray *names;

    [manager createDirectoryAtPath:markerDirectory
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL];
    names = [manager contentsOfDirectoryAtPath:directory error:NULL];

    for (NSString *name in names) {
        NSString *path;
        NSString *extension;
        NSString *marker;
        BOOL isDirectory = NO;

        if ([name hasPrefix:@"."]) continue;
        path = [directory stringByAppendingPathComponent:name];
        if (![manager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) continue;

        extension = [[name pathExtension] lowercaseString];
        if (![extension isEqualToString:@"jpg"] &&
            ![extension isEqualToString:@"jpeg"] &&
            ![extension isEqualToString:@"png"] &&
            ![extension isEqualToString:@"mp4"] &&
            ![extension isEqualToString:@"mov"] &&
            ![extension isEqualToString:@"m4v"]) continue;

        marker = [markerDirectory stringByAppendingPathComponent:name];
        if ([manager fileExistsAtPath:marker]) continue;

        os_logf(self, @"Retrying photo save: %@", name);
        if ([self saveToPhotos:path type:@"" timeout:20]) {
            [self writeSavedMarkerForPath:path];
        }
    }
    [pool release];
}

- (int)handleCancel:(const char *)path {
    char sessionId[64];
    if (!os_query_value(path, "sessionId", sessionId, sizeof sessionId)) return 400;
    {
        BOOL current = (gSession.active &&
                        strcmp(sessionId, gSession.sessionId) == 0);
        BOOL recent = (gLastSessionId[0] != '\0' &&
                       strcmp(sessionId, gLastSessionId) == 0);

        if (current || recent) {
            if (current) {
                gSession.active = 0;
                gSession.remaining = 0;
            }
            [self performSelectorOnMainThread:@selector(handleCancelledSession)
                                   withObject:nil
                                waitUntilDone:NO];
            os_logf(self, @"Sender cancelled the session");
            return 200;
        }
    }
    return 403;
}

- (void)handleHTTP:(mbedtls_ssl_context *)ssl peer:(const char *)peer {
    char line[2048];
    OSRequest request;
    int n;

    memset(&request, 0, sizeof request);
    request.contentLength = 0;

    n = os_read_line(ssl, line, sizeof line);
    if (n <= 0) return;
    if (sscanf(line, "%15s %1023s", request.method, request.path) != 2) return;

    while ((n = os_read_line(ssl, line, sizeof line)) > 0) {
        if (strncasecmp(line, "Content-Length:", 15) == 0) {
            request.contentLength = strtoll(line + 15, NULL, 10);
        } else if (strncasecmp(line, "Transfer-Encoding:", 18) == 0) {
            if (strcasestr(line, "chunked") != NULL) request.chunked = 1;
        } else if (strncasecmp(line, "Connection:", 11) == 0) {
            if (strcasestr(line, "close") != NULL) request.closeConnection = 1;
        }
    }

    if (strncmp(request.path, "/api/localsend/v2/upload", 24) == 0) {
        int status = [self handleUpload:ssl request:&request identity:(OSIdentity *)_identity];
        os_logf(self, @"%s /api/localsend/v2/upload ← %s (%d)", request.method, peer, status);
        [self sendResponse:ssl status:status body:nil];
        return;
    }

    {
        unsigned char *body = NULL;
        size_t bodyLength = 0;
        int status = 200;
        NSString *response = nil;

        if (request.contentLength > 0 || request.chunked) {
            if (os_read_body_alloc(ssl, &request, &body, &bodyLength) != 0) {
                os_logf(self, @"Failed to read request body from %s", peer);
                [self sendResponse:ssl status:400 body:@"{\"message\":\"bad body\"}"];
                free(body);
                return;
            }
        }

        os_logf(self, @"%s %s ← %s", request.method, request.path, peer);

        if (strncmp(request.path, "/api/localsend/v2/register", 26) == 0) {
            if (bodyLength > 0) {
                [self addDeviceFromRegisterJSON:body length:bodyLength ip:peer];
            }
            response = [self registerJSON];
        } else if (strncmp(request.path, "/api/localsend/v2/info", 22) == 0) {
            response = [self registerJSON];
        } else if (strncmp(request.path, "/api/localsend/v2/prepare-upload", 33) == 0) {
            status = [self handlePrepare:body length:bodyLength response:&response];
        } else if (strncmp(request.path, "/api/localsend/v2/cancel", 25) == 0) {
            status = [self handleCancel:request.path];
        } else {
            status = 404;
            response = @"{\"message\":\"not found\"}";
        }

        [self sendResponse:ssl status:status body:response];
        free(body);
    }
}

- (void)dealloc {
    [self stop];
    os_identity_free((OSIdentity *)_identity);
    _identity = NULL;
    [_alias release];
    [_model release];
    [_fingerprint release];
    [_localIP release];
    [_status release];
    [_log release];
    [super dealloc];
}

@end
