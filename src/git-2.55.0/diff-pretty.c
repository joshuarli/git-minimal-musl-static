#include "git-compat-util.h"
#include "diff-pretty-integration.h"
#include "pager.h"
#include "thread-utils.h"

static struct diff_pretty_session *native_session;
static int native_failed;
static int native_quit;
static int native_command_session;
static char native_error[256];

struct diff_pretty_capture {
	int read_fd;
	pthread_t reader;
	int reader_status;
};

static struct diff_pretty_capture *native_capture;

static void diff_pretty_atexit(void);
static void *diff_pretty_capture_reader(void *data);

/* The FFI accepts UTF-8 chunks, so do not pass it the lead bytes of a
 * multibyte code point without the continuation bytes that follow them. */
static size_t incomplete_utf8_suffix(const char *data, size_t len)
{
	unsigned char first;
	size_t start, expected;

	if (!len)
		return 0;

	start = len - 1;
	while (start && ((unsigned char)data[start] & 0xc0) == 0x80)
		start--;
	first = (unsigned char)data[start];
	if (first < 0x80)
		return 0;
	if ((first & 0xe0) == 0xc0)
		expected = 2;
	else if ((first & 0xf0) == 0xe0)
		expected = 3;
	else if ((first & 0xf8) == 0xf0)
		expected = 4;
	else
		return 0;

	return len - start < expected ? len - start : 0;
}

static void remember_native_error(const char *fallback)
{
	const char *error = native_session
		? diff_pretty_last_error(native_session)
		: NULL;

	xsnprintf(native_error, sizeof(native_error), "%s",
		   error ? error : fallback);
	native_failed = 1;
}

int diff_pretty_setup(struct repository *repository)
{
	const char *pager;
	struct diff_pretty_config config = {
		.version = DIFF_PRETTY_ABI_VERSION,
		.size = sizeof(config),
		.paging = DIFF_PRETTY_PAGING_ALWAYS,
		.output_fd = 1,
		.tty_fd = -1,
	};

	if (native_session)
		return 1;
	native_failed = 0;
	native_quit = 0;
	native_command_session = 0;
	native_error[0] = '\0';

	pager = git_pager(repository, isatty(1));
	if (!pager || strcmp(pager, "builtin:diff-pretty"))
		return 0;

	native_session = diff_pretty_begin(&config);
	if (!native_session) {
		xsnprintf(native_error, sizeof(native_error),
			   "unable to initialize native pager");
		native_failed = 1;
		return -1;
	}

	setenv("GIT_PAGER_IN_USE", "true", 1);
	atexit(diff_pretty_atexit);
	return 1;
}

/* `git log` and `git show` emit one ordered commit stream per commit,
 * optionally followed by semantic diff events. Keep their renderer session
 * alive until the command has emitted every commit. */
int diff_pretty_setup_log(struct repository *repository)
{
	int status = diff_pretty_setup(repository);

	if (status > 0)
		native_command_session = 1;
	return status;
}

int diff_pretty_active(void)
{
	return native_session && !native_failed && !native_quit;
}

void diff_pretty_emit_event(unsigned kind, unsigned flags,
			    const char *data, size_t len)
{
	int status;

	if (!diff_pretty_active())
		return;
	status = diff_pretty_push_event(native_session, kind, flags,
					(const unsigned char *)data, len);
	if (status == DIFF_PRETTY_STATUS_QUIT)
		native_quit = 1;
	else if (status < 0)
		remember_native_error("unable to render diff event");
}

void diff_pretty_emit_patch(const char *data, size_t len)
{
	int status;

	if (!diff_pretty_active())
		return;
	status = diff_pretty_push_patch(native_session,
					(const unsigned char *)data, len);
	if (status == DIFF_PRETTY_STATUS_QUIT)
		native_quit = 1;
	else if (status < 0)
		remember_native_error("unable to render Git metadata");
}

static void *diff_pretty_capture_reader(void *data)
{
	struct diff_pretty_capture *capture = data;
	char buffer[8192 + 3];
	char pending[3];
	ssize_t read_length;
	size_t length, pending_len = 0, suffix_len;

	for (;;) {
		if (pending_len)
			memcpy(buffer, pending, pending_len);
		do {
			read_length = read(capture->read_fd, buffer + pending_len,
					   sizeof(buffer) - pending_len);
		} while (read_length < 0 && errno == EINTR);
		if (read_length < 0) {
			remember_native_error("unable to read Git metadata pipe");
			capture->reader_status = -1;
			break;
		}
		if (!read_length)
			break;

		length = pending_len + (size_t)read_length;
		pending_len = 0;
		suffix_len = incomplete_utf8_suffix(buffer, length);
		if (suffix_len) {
			memcpy(pending, buffer + length - suffix_len, suffix_len);
			pending_len = suffix_len;
			length -= suffix_len;
		}
		if (length)
			diff_pretty_emit_patch(buffer, length);
	}
	if (pending_len)
		diff_pretty_emit_patch(pending, pending_len);
	if (native_failed)
		capture->reader_status = -1;
	close(capture->read_fd);
	return NULL;
}

int diff_pretty_capture_begin(FILE **stream, FILE **saved)
{
	struct diff_pretty_capture *capture_state;
	FILE *capture;
	int pipe_fds[2];

	if (!diff_pretty_active())
		return 0;
	if (!stream || !saved || !*stream) {
		remember_native_error("unable to capture Git metadata");
		return -1;
	}
	if (native_capture) {
		remember_native_error("nested Git metadata capture");
		return -1;
	}

	if (pipe(pipe_fds)) {
		remember_native_error("unable to create Git metadata pipe");
		return -1;
	}
	capture = fdopen(pipe_fds[1], "w");
	if (!capture) {
		close(pipe_fds[0]);
		close(pipe_fds[1]);
		remember_native_error("unable to create Git metadata buffer");
		return -1;
	}
	if (setvbuf(capture, NULL, _IONBF, 0)) {
		fclose(capture);
		close(pipe_fds[0]);
		remember_native_error("unable to configure Git metadata pipe");
		return -1;
	}

	capture_state = xcalloc(1, sizeof(*capture_state));
	capture_state->read_fd = pipe_fds[0];
	if (pthread_create(&capture_state->reader, NULL,
			   diff_pretty_capture_reader, capture_state)) {
		free(capture_state);
		fclose(capture);
		close(pipe_fds[0]);
		remember_native_error("unable to start Git metadata reader");
		return -1;
	}
	native_capture = capture_state;

	*saved = *stream;
	*stream = capture;
	return 1;
}

int diff_pretty_capture_end(FILE **stream, FILE *saved)
{
	FILE *capture;
	int status = 0;
	struct diff_pretty_capture *capture_state;

	if (!stream || !*stream || !saved) {
		remember_native_error("unable to finish Git metadata capture");
		return -1;
	}

	capture = *stream;
	capture_state = native_capture;
	if (!capture_state) {
		remember_native_error("missing Git metadata reader");
		status = -1;
	}
	if (fclose(capture)) {
		remember_native_error("unable to close Git metadata pipe");
		status = -1;
	}
	if (capture_state) {
		if (pthread_join(capture_state->reader, NULL)) {
			remember_native_error("unable to join Git metadata reader");
			status = -1;
		}
		if (capture_state->reader_status < 0)
			status = -1;
		free(capture_state);
		native_capture = NULL;
	}
	*stream = saved;
	return status;
}

int diff_pretty_end_after_diff(void)
{
	if (native_command_session)
		return 0;
	return diff_pretty_end();
}

int diff_pretty_end(void)
{
	int status;

	if (!native_session)
		return 0;

	if (native_failed) {
		status = -1;
	} else if (native_quit) {
		status = 0;
	} else {
		status = diff_pretty_finish(native_session);
		if (status < 0) {
			remember_native_error("unable to finish native pager");
			status = -1;
		} else {
			status = diff_pretty_page(native_session);
			if (status < 0) {
				remember_native_error("unable to page rendered diff");
				status = -1;
			}
		}
	}

	if (status < 0 && *native_error)
		fprintf(stderr, "diff-pretty: %s\n", native_error);

	diff_pretty_abort(native_session);
	native_session = NULL;
	native_quit = 0;
	native_command_session = 0;
	unsetenv("GIT_PAGER_IN_USE");
	return status < 0 ? -1 : 0;
}

static void diff_pretty_atexit(void)
{
	(void)diff_pretty_end();
}
