#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

#ifndef FIXTURE_ROLE
#error FIXTURE_ROLE is required
#endif

static int self_path(char *buffer, size_t size) {
  char raw[PATH_MAX];
#if defined(__APPLE__)
  uint32_t length = (uint32_t)sizeof(raw);
  if (_NSGetExecutablePath(raw, &length) != 0) return -1;
#else
  ssize_t length = readlink("/proc/self/exe", raw, sizeof(raw) - 1);
  if (length < 0 || (size_t)length >= sizeof(raw) - 1) return -1;
  raw[length] = '\0';
#endif
  if (size < PATH_MAX) return -1;
  return realpath(raw, buffer) == NULL ? -1 : 0;
}

static int owner_path(char *destination, size_t size, const char *name) {
  char executable[PATH_MAX];
  char *slash;
  if (self_path(executable, sizeof(executable)) != 0) return -1;
  slash = strrchr(executable, '/');
  if (slash == NULL) return -1;
  *slash = '\0';
  slash = strrchr(executable, '/');
  if (slash == NULL) return -1;
  *slash = '\0';
  return snprintf(destination, size, "%s/%s", executable, name) > 0 ? 0 : -1;
}

static int write_text(const char *path, const char *text) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  size_t length = strlen(text);
  ssize_t written;
  if (fd < 0) return -1;
  written = write(fd, text, length);
  (void)close(fd);
  return written == (ssize_t)length ? 0 : -1;
}

static const char *presence(const char *name) {
  return getenv(name) == NULL ? "absent" : "present";
}

int main(int argc, char **argv) {
  char path[PATH_MAX];
#if FIXTURE_ROLE == 1
  if (owner_path(path, sizeof(path), "loader-control.pid") != 0) return 70;
  char pid[64];
  snprintf(pid, sizeof(pid), "%ld\n", (long)getpid());
  return write_text(path, pid) == 0 ? 0 : 71;
#elif FIXTURE_ROLE == 2
  if (owner_path(path, sizeof(path), "nm.pid") != 0) return 72;
  char pid[64];
  snprintf(pid, sizeof(pid), "%ld\n", (long)getpid());
  if (write_text(path, pid) != 0) return 73;
  if (owner_path(path, sizeof(path), "nm.argv.raw") != 0) return 74;
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) return 75;
  for (int index = 0; index < argc; index += 1) {
    dprintf(fd, "%d|%s\n", index, argv[index]);
  }
  close(fd);
  if (owner_path(path, sizeof(path), "nm.poison.raw") != 0) return 76;
  char poison[1024];
  snprintf(poison, sizeof(poison),
      "inherited-poison|HOME=%s|TMPDIR=%s|PKG_CONFIG_PATH=%s|"
      "PKG_CONFIG_LIBDIR=%s|DYLD_INSERT_LIBRARIES=%s|"
      "DYLD_LIBRARY_PATH=%s|LD_PRELOAD=%s|LD_LIBRARY_PATH=%s|"
      "LOADER_EVENTS=%s|FAKE_SECRET=%s\n",
      presence("HOME"), presence("TMPDIR"), presence("PKG_CONFIG_PATH"),
      presence("PKG_CONFIG_LIBDIR"), presence("DYLD_INSERT_LIBRARIES"),
      presence("DYLD_LIBRARY_PATH"), presence("LD_PRELOAD"),
      presence("LD_LIBRARY_PATH"), presence("LOADER_EVENTS"),
      presence("FAKE_SECRET"));
  if (write_text(path, poison) != 0) return 77;
  fputs("private native nm failure secret\n", stderr);
  return 9;
#elif FIXTURE_ROLE == 3
  if (owner_path(path, sizeof(path), "go.launched") != 0) return 78;
  return write_text(path, "launched\n") == 0 ? 97 : 79;
#elif FIXTURE_ROLE == 4
  if (owner_path(path, sizeof(path), "pkg-config.launched") != 0) return 80;
  return write_text(path, "launched\n") == 0 ? 97 : 81;
#else
#error unsupported FIXTURE_ROLE
#endif
}
