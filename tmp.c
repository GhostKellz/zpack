#include <stdio.h>
#include <zlib.h>

int main(void) {
    unsigned long bound = compressBound(1024);
    printf("compressBound=%lu\n", bound);
    return 0;
}
