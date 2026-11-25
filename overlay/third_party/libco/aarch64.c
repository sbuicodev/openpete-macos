/* AArch64 (AAPCS64) backend for libco, local addition for macOS/Linux arm64.
 *
 * The context switch is a real assembled function, so no executable data
 * section or mprotect is needed (Apple Silicon forbids W+X pages).
 *
 * Context layout (handle points at it), 8-byte slots:
 *   [0] sp   [1] lr(x30)   [2..11] x19..x28   [12] x29
 *   [14..21] d8..d15
 */
#define LIBCO_C
#include "libco.h"
#include "settings.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__APPLE__)
  #define LIBCO_SYM(name) "_" #name
#else
  #define LIBCO_SYM(name) #name
#endif

static thread_local unsigned long long co_active_buffer[64];
static thread_local cothread_t co_active_handle = 0;

void libco_aarch64_swap(cothread_t to, cothread_t from);
void libco_aarch64_entry(void);

__asm__(
  ".text\n"
  ".p2align 2\n"
  ".globl " LIBCO_SYM(libco_aarch64_swap) "\n"
  LIBCO_SYM(libco_aarch64_swap) ":\n"
  "  mov  x16, sp\n"
  "  stp  x16, x30, [x1, #0]\n"
  "  stp  x19, x20, [x1, #16]\n"
  "  stp  x21, x22, [x1, #32]\n"
  "  stp  x23, x24, [x1, #48]\n"
  "  stp  x25, x26, [x1, #64]\n"
  "  stp  x27, x28, [x1, #80]\n"
  "  str  x29,      [x1, #96]\n"
  "  stp  d8,  d9,  [x1, #112]\n"
  "  stp  d10, d11, [x1, #128]\n"
  "  stp  d12, d13, [x1, #144]\n"
  "  stp  d14, d15, [x1, #160]\n"
  "  ldp  x16, x30, [x0, #0]\n"
  "  mov  sp, x16\n"
  "  ldp  x19, x20, [x0, #16]\n"
  "  ldp  x21, x22, [x0, #32]\n"
  "  ldp  x23, x24, [x0, #48]\n"
  "  ldp  x25, x26, [x0, #64]\n"
  "  ldp  x27, x28, [x0, #80]\n"
  "  ldr  x29,      [x0, #96]\n"
  "  ldp  d8,  d9,  [x0, #112]\n"
  "  ldp  d10, d11, [x0, #128]\n"
  "  ldp  d12, d13, [x0, #144]\n"
  "  ldp  d14, d15, [x0, #160]\n"
  "  ret\n"
  /* First switch into a new cothread lands here: x19 = entrypoint,
   * x20 = crash handler (entrypoints must never return). */
  ".p2align 2\n"
  ".globl " LIBCO_SYM(libco_aarch64_entry) "\n"
  LIBCO_SYM(libco_aarch64_entry) ":\n"
  "  mov  x29, #0\n"
  "  blr  x19\n"
  "  blr  x20\n"
  "  brk  #0\n"
);

static void crash(void) {
  LIBCO_ASSERT(0);  /* called only if cothread_t entrypoint returns */
}

cothread_t co_active(void) {
  if(!co_active_handle) co_active_handle = &co_active_buffer;
  return co_active_handle;
}

cothread_t co_derive(void* memory, unsigned int size, void (*entrypoint)(void)) {
  unsigned long long* ctx;
  unsigned long long stack_top;
  if(!co_active_handle) co_active_handle = &co_active_buffer;
  if(!memory || size < 1024) return (cothread_t)0;

  ctx = (unsigned long long*)memory;
  for(unsigned i = 0; i < 22; i++) ctx[i] = 0;
  stack_top = ((unsigned long long)memory + size) & ~15ULL;
  ctx[0]  = stack_top;
  ctx[1]  = (unsigned long long)libco_aarch64_entry;
  ctx[2]  = (unsigned long long)entrypoint;  /* x19 */
  ctx[3]  = (unsigned long long)crash;       /* x20 */
  return (cothread_t)memory;
}

cothread_t co_create(unsigned int size, void (*entrypoint)(void)) {
  void* memory = LIBCO_MALLOC(size);
  if(!memory) return (cothread_t)0;
  return co_derive(memory, size, entrypoint);
}

void co_delete(cothread_t handle) {
  LIBCO_FREE(handle);
}

void co_switch(cothread_t handle) {
  cothread_t co_previous_handle = co_active_handle;
  libco_aarch64_swap(co_active_handle = handle, co_previous_handle);
}

int co_serializable(void) {
  return 1;
}

#ifdef __cplusplus
}
#endif
