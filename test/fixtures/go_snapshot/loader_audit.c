#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

static int executable_path(char *buffer, size_t size) {
#if defined(__APPLE__)
  uint32_t length = (uint32_t)size;
  return _NSGetExecutablePath(buffer, &length) == 0 ? 0 : -1;
#else
  ssize_t length = readlink("/proc/self/exe", buffer, size - 1);
  if (length < 0 || (size_t)length >= size - 1) return -1;
  buffer[length] = '\0';
  return 0;
#endif
}

__attribute__((constructor)) static void record_load(void) {
  const char *sink = getenv("LOADER_EVENTS");
  char raw[PATH_MAX];
  char canonical[PATH_MAX];
  char line[PATH_MAX + 96];
  struct stat status;
  int fd;
  int length;

  if (sink == NULL || sink[0] != '/' || strchr(sink, '\n') != NULL ||
      strchr(sink, '\r') != NULL || lstat(sink, &status) != 0 ||
      !S_ISREG(status.st_mode) || S_ISLNK(status.st_mode) ||
      executable_path(raw, sizeof(raw)) != 0 ||
      realpath(raw, canonical) == NULL) {
    return;
  }
  fd = open(sink, O_WRONLY | O_APPEND | O_CLOEXEC);
  if (fd < 0) return;
  length = snprintf(line, sizeof(line), "load|pid=%ld|exe=%s\n",
                    (long)getpid(), canonical);
  if (length > 0 && (size_t)length < sizeof(line)) {
    (void)write(fd, line, (size_t)length);
  }
  (void)close(fd);
}
