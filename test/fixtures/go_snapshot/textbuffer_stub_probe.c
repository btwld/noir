#include "../../../external/opentui/packages/go/opentui.h"
#include <string.h>

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  if (strcmp(argv[1], "textBufferConcat") == 0) {
    (void)textBufferConcat((TextBuffer*)0, (TextBuffer*)0);
  } else if (strcmp(argv[1], "textBufferResize") == 0) {
    textBufferResize((TextBuffer*)0, 0);
  } else if (strcmp(argv[1], "textBufferGetCapacity") == 0) {
    (void)textBufferGetCapacity((TextBuffer*)0);
  } else {
    return 3;
  }
  return 4;
}
