#include <unistd.h>
#include <fcntl.h>

int main(void) {
    int fd = open("/app/input.txt", O_RDONLY);
    if (fd < 0) {
        return 1;
    }
    char buf[64];
    ssize_t n = read(fd, buf, sizeof buf);
    write(1, buf, n);
    close(fd);
    return 0;
}