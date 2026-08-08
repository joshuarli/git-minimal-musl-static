#ifndef DIFF_PRETTY_INTEGRATION_H
#define DIFF_PRETTY_INTEGRATION_H

#include <stdio.h>

#include "diff_pretty.h"

struct repository;

/* The adapter is inert unless DIFF_PRETTY_ENABLED is defined at build time. */
int diff_pretty_setup(struct repository *repository);
int diff_pretty_setup_log(struct repository *repository);
int diff_pretty_active(void);
void diff_pretty_emit_event(unsigned kind, unsigned flags,
			    const char *data, size_t len);
void diff_pretty_emit_patch(const char *data, size_t len);
int diff_pretty_capture_begin(FILE **stream, FILE **saved);
int diff_pretty_capture_end(FILE **stream, FILE *saved);
int diff_pretty_end_after_diff(void);
int diff_pretty_end(void);

#endif
