#include "git-compat-util.h"
#include "diff-pretty-integration.h"
#include "pager.h"

static struct diff_pretty_session *native_session;
static int native_failed;
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
	unsetenv("GIT_PAGER_IN_USE");
	return status < 0 ? -1 : 0;
}

static void diff_pretty_atexit(void)
{
	(void)diff_pretty_end();
}
