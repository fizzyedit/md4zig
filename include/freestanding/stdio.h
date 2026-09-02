/* Freestanding-wasm shim. md4c.c includes <stdio.h> unconditionally but its only
   use (a memory-statistics sprintf block) sits behind `#if 0`, so this is empty
   on purpose — nothing to declare. */
#ifndef MD4ZIG_SHIM_STDIO_H
#define MD4ZIG_SHIM_STDIO_H
#endif
