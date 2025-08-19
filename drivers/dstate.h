/* dstate.h - Network UPS Tools driver-side state management

   Copyright (C)
	2003	Russell Kroll <rkroll@exploits.org>
	2012-2017	Arnaud Quette <arnaud.quette@free.fr>
	2020-2025	Jim Klimov <jimklimov+nut@gmail.com>

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
*/

#ifndef DSTATE_H_SEEN
#define DSTATE_H_SEEN 1

#include "common.h"
#include "timehead.h"
#include "state.h"
#include "attribute.h"

#include "parseconf.h"
#include "upshandler.h"

#ifdef WIN32
# include "wincompat.h"
#endif	/* WIN32 */

#define DS_LISTEN_BACKLOG 16
#define DS_MAX_READ 256		/* don't read forever from upsd */

#ifndef MAX_STRING_SIZE
#define MAX_STRING_SIZE	128
#endif

/* track client connections */
typedef struct conn_s {
	TYPE_FD	fd;
#ifdef WIN32
	char    buf[LARGEBUF];
	OVERLAPPED read_overlapped;
#endif	/* WIN32 */
	PCONF_CTX_t	ctx;
	struct conn_s	*prev;
	struct conn_s	*next;
	int	nobroadcast;	/* connections can request to ignore send_to_all() updates */
	int	readzero;	/* how many times in a row we had zero bytes read; see DSTATE_CONN_READZERO_THROTTLE_USEC and DSTATE_CONN_READZERO_THROTTLE_MAX */
	int	closing;	/* raised during LOGOUT processing, to close the socket when time is right */
} conn_t;

/* sleep after read()ing zero bytes */
#define DSTATE_CONN_READZERO_THROTTLE_USEC	500

/* close socket after read()ing zero bytes this many times in a row */
#define DSTATE_CONN_READZERO_THROTTLE_MAX	5

#include "main.h"	/* for set_exit_flag(); uses conn_t itself */

	extern	struct	ups_handler	upsh;

	/* asynchronous (nonblocking) Vs synchronous (blocking) I/O
	 * Defaults to nonblocking, for backward compatibility */
	extern	int	do_synchronous;

char * dstate_init(const char *prog, const char *devname);
int dstate_poll_fds(struct timeval timeout, TYPE_FD extrafd);
int vdstate_setinfo(const char *var, const char *fmt, va_list ap);
int dstate_setinfo(const char *var, const char *fmt, ...)
	__attribute__ ((__format__ (__printf__, 2, 3)));
int dstate_setinfo_dynamic(const char *var, const char *fmt_dynamic, const char *fmt_reference, ...)
	__attribute__ ((__format__ (__printf__, 3, 4)));
int vdstate_addenum(const char *var, const char *fmt, va_list ap);
int dstate_addenum(const char *var, const char *fmt, ...)
	__attribute__ ((__format__ (__printf__, 2, 3)));
int dstate_addenum_dynamic(const char *var, const char *fmt_dynamic, const char *fmt_reference, ...)
	__attribute__ ((__format__ (__printf__, 3, 4)));
int dstate_addrange(const char *var, const int min, const int max);
void dstate_setflags(const char *var, int flags);
void dstate_addflags(const char *var, const int addflags);
void dstate_delflags(const char *var, const int delflags);
void dstate_setaux(const char *var, long aux);
const char *dstate_getinfo(const char *var);
void dstate_addcmd(const char *cmdname);
int dstate_delinfo_olderthan(const char *var, const st_tree_timespec_t *cutoff);
int dstate_delinfo(const char *var);
int dstate_delenum(const char *var, const char *val);
int dstate_delrange(const char *var, const int min, const int max);
int dstate_delcmd(const char *cmd);
void dstate_free(void);
const st_tree_t *dstate_getroot(void);
const cmdlist_t *dstate_getcmdlist(void);

void dstate_dataok(void);
void dstate_datastale(void);

int dstate_is_stale(void);

/* clean out the temp space for a new pass */
void status_init(void);

/* check if a status element has been set, return 0 if not, 1 if yes
 * (considering a whole-word token in temporary status_buf) */
int status_get(const char *buf);

/* add a status element */
void status_set(const char *buf);

/* write the temporary status_buf into ups.status */
void status_commit(void);

/* similar functions for experimental.ups.mode.buzzwords, where tracked
 * dynamically (e.g. due to ECO/ESS/HE/Smart modes supported by the device) */
void buzzmode_init(void);
int  buzzmode_get(const char *buf);
void buzzmode_set(const char *buf);
void buzzmode_commit(void);

/* similar functions for ups.alarm */
void alarm_init(void);
void alarm_set(const char *buf);
void alarm_commit(void);
void device_alarm_init(void);
void device_alarm_commit(const int device_number);

int dstate_detect_phasecount(
        const char *xput_prefix,
        const int may_change_dstate,
        int *inited_phaseinfo,
        int *num_phases,
        const int may_reevaluate);

void dstate_dump(void);

#endif	/* DSTATE_H_SEEN */
