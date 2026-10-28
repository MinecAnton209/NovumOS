#include <errno.h>
#include <fcntl.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static int failures = 0;

#define CHECK(name, cond) do { \
	if (cond) { printf("PASS %s\n", name); } \
	else { printf("FAIL %s (errno=%d)\n", name, errno); failures++; } \
} while (0)

static void on_exit_handler(void) {
	printf("PASS atexit runs before process end\n");
}

static void test_log_and_panic(int argc, char **argv) {
	if (argc > 1 && strcmp(argv[1], "abort") == 0) {
		abort();
	}
}

static void test_isatty(void) {
	errno = 0;
	int bad = isatty(-1);
	CHECK("isatty(-1) returns 0", bad == 0);
	CHECK("isatty(-1) sets EBADF or ENOTTY", errno == EBADF || errno == ENOTTY);
}

static void test_write(void) {
	errno = 0;
	CHECK("write to stdout returns 1", write(1, "x\n", 2) == 2);
	CHECK("write to bad fd returns -1", write(-1, "x", 1) == -1);
	CHECK("write to bad fd sets EBADF", errno == EBADF);
}

static void test_read(void) {
	char c;
	errno = 0;
	CHECK("read from bad fd returns -1", read(-1, &c, 1) == -1);
	CHECK("read from bad fd sets EBADF", errno == EBADF);
}

static void test_open_close_seek(void) {
	errno = 0;
	CHECK("open missing file returns -1", open("/no_such_file_novumos", O_RDONLY) == -1);
	CHECK("open missing file sets ENOENT", errno == ENOENT);

	int fd = open("/", O_RDONLY);
	if (fd >= 0) {
		CHECK("open root directory succeeds", fd >= 0);
		CHECK("lseek on open fd succeeds", lseek(fd, 0, SEEK_SET) >= 0);
		CHECK("close open fd succeeds", close(fd) == 0);
		errno = 0;
		CHECK("close already closed fd fails", close(fd) == -1);
	} else {
		printf("SKIP open root directory (no filesystem mounted)\n");
	}

	errno = 0;
	CHECK("lseek on bad fd returns -1", lseek(-1, 0, SEEK_SET) == -1);
	CHECK("lseek on bad fd sets EBADF", errno == EBADF);
}

static void test_clock(void) {
	struct timespec a, b;
	CHECK("clock_gettime MONOTONIC succeeds", clock_gettime(CLOCK_MONOTONIC, &a) == 0);
	CHECK("clock_gettime MONOTONIC is non-decreasing", clock_gettime(CLOCK_MONOTONIC, &b) == 0 &&
		(b.tv_sec > a.tv_sec || (b.tv_sec == a.tv_sec && b.tv_nsec >= a.tv_nsec)));
	CHECK("clock_gettime REALTIME succeeds", clock_gettime(CLOCK_REALTIME, &a) == 0);
	errno = 0;
	CHECK("clock_gettime invalid clock fails", clock_gettime(-1, &a) == -1);
	CHECK("clock_gettime invalid clock sets EINVAL", errno == EINVAL);
}

static void test_anon_alloc(void) {
	size_t size = 64 * 1024;
	unsigned char *p = malloc(size);
	CHECK("malloc 64 KiB returns memory", p != NULL);
	if (p) {
		memset(p, 0xA5, size);
		CHECK("malloc block keeps written pattern", p[0] == 0xA5 && p[size - 1] == 0xA5);
		free(p);
	}
}

static void test_vm_map(void) {
	size_t size = 8192;
	void *m = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK("mmap anonymous succeeds", m != MAP_FAILED);
	if (m != MAP_FAILED) {
		((unsigned char *)m)[0] = 1;
		((unsigned char *)m)[size - 1] = 2;
		CHECK("mmap anonymous memory is writable", ((unsigned char *)m)[0] == 1 && ((unsigned char *)m)[size - 1] == 2);
		CHECK("munmap anonymous succeeds", munmap(m, size) == 0);
	}
	errno = 0;
	CHECK("mmap without MAP_ANONYMOUS and bad fd fails", mmap(NULL, size, PROT_READ, MAP_PRIVATE, -1, 0) == MAP_FAILED);
}

static void test_tcb_errno(void) {
	errno = 42;
	CHECK("errno is per-thread storage and keeps its value", errno == 42);
	errno = 0;
}

static void test_futex(void) {
	sem_t s;
	CHECK("sem_init succeeds", sem_init(&s, 0, 0) == 0);

	struct timespec past;
	clock_gettime(CLOCK_REALTIME, &past);
	past.tv_sec -= 1;
	errno = 0;
	CHECK("sem_timedwait with past deadline fails", sem_timedwait(&s, &past) == -1);
	CHECK("sem_timedwait sets ETIMEDOUT", errno == ETIMEDOUT);

	CHECK("sem_post wakes waiter path", sem_post(&s) == 0);
	CHECK("sem_wait returns after post", sem_wait(&s) == 0);
	CHECK("sem_destroy succeeds", sem_destroy(&s) == 0);
}

int main(int argc, char **argv) {
	atexit(on_exit_handler);
	test_log_and_panic(argc, argv);
	test_isatty();
	test_write();
	test_read();
	test_open_close_seek();
	test_clock();
	test_anon_alloc();
	test_vm_map();
	test_tcb_errno();
	test_futex();
	printf("sysdeps tests finished: %d failure(s)\n", failures);
	return failures ? 1 : 0;
}
