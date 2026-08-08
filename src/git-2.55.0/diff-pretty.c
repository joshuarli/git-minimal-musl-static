#include "git-compat-util.h"
#include "diff-pretty-integration.h"
#include "pager.h"

static struct diff_pretty_session *native_session;
static int native_failed;
static int native_command_session;
static char native_error[256];

static void diff_pretty_atexit(void);

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
	return native_session && !native_failed;
}

void diff_pretty_emit_event(unsigned kind, unsigned flags,
			    const char *data, size_t len)
{
	int status;

	if (!diff_pretty_active())
		return;
	status = diff_pretty_push_event(native_session, kind, flags,
					(const unsigned char *)data, len);
	if (status < 0)
		remember_native_error("unable to render diff event");
}

void diff_pretty_emit_patch(const char *data, size_t len)
{
	int status;

	if (!diff_pretty_active())
		return;
	status = diff_pretty_push_patch(native_session,
					(const unsigned char *)data, len);
	if (status < 0)
		remember_native_error("unable to render Git metadata");
}

int diff_pretty_capture_begin(FILE **stream, FILE **saved)
{
	FILE *capture;

	if (!diff_pretty_active())
		return 0;
	if (!stream || !saved || !*stream) {
		remember_native_error("unable to capture Git metadata");
		return -1;
	}

	capture = tmpfile();
	if (!capture) {
		remember_native_error("unable to create Git metadata buffer");
		return -1;
	}

	*saved = *stream;
	*stream = capture;
	return 1;
}

int diff_pretty_capture_end(FILE **stream, FILE *saved)
{
	FILE *capture;
	char buffer[8192];
	int status = 0;
	size_t length;

	if (!stream || !*stream || !saved) {
		remember_native_error("unable to finish Git metadata capture");
		return -1;
	}

	capture = *stream;
	if (fflush(capture) || fseek(capture, 0, SEEK_SET)) {
		remember_native_error("unable to read Git metadata buffer");
		status = -1;
		goto close_capture;
	}

	while ((length = fread(buffer, 1, sizeof(buffer), capture)) != 0) {
		diff_pretty_emit_patch(buffer, length);
		if (native_failed) {
			status = -1;
			break;
		}
	}
	if (ferror(capture)) {
		remember_native_error("unable to read Git metadata buffer");
		status = -1;
	}

close_capture:
	if (fclose(capture)) {
		remember_native_error("unable to close Git metadata buffer");
		status = -1;
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
	native_command_session = 0;
	unsetenv("GIT_PAGER_IN_USE");
	return status < 0 ? -1 : 0;
}

static void diff_pretty_atexit(void)
{
	(void)diff_pretty_end();
}
