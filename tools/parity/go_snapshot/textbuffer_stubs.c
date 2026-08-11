#include "../../../external/opentui/packages/go/opentui.h"
#include <stdio.h>
#include <stdlib.h>

static _Noreturn void unexpected_stub_call(const char* symbol) {
  fprintf(stderr, "unexpected OpenTUI parity-link stub call: %s\n", symbol);
  fflush(stderr);
  abort();
}

TextBuffer* textBufferConcat(TextBuffer* tb1, TextBuffer* tb2) {
  (void)tb1;
  (void)tb2;
  unexpected_stub_call("textBufferConcat");
}

void textBufferResize(TextBuffer* textBuffer, uint32_t newLength) {
  (void)textBuffer;
  (void)newLength;
  unexpected_stub_call("textBufferResize");
}

uint32_t textBufferGetCapacity(TextBuffer* textBuffer) {
  (void)textBuffer;
  unexpected_stub_call("textBufferGetCapacity");
}
