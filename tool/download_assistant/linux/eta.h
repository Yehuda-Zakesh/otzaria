/* Time-left estimate, the same algorithm on every platform (reference:
 * lib/utils/download_eta_estimator.dart). Plain C, no GLib. */
#pragma once

#define OTZ_ETA_STALL_SECONDS 5.0
#define OTZ_ETA_RESTART_SECONDS 30.0

typedef enum { OTZ_WORK_COPY, OTZ_WORK_HASH, OTZ_WORK_KINDS } OtzWorkKind;

/* Transfer rate: decayed sums of bytes and time, blended with the average.
 * Silence is not sampled; the next sample covers the gap (a lone stall: 2 s). */
typedef struct {
  double tau;
  double sb, st;
  int has_last;
  double last_t;
  long long last_bytes;
  double active, session_bytes;
  double warm_t, warm_bytes;
  int warm_n, warmed;
  double max_gap;
  int has_stall_recovery;
  double last_stall_recovery_t, iso_deficit;
} OtzRate;

void otz_rate_init(OtzRate *rate, double tau);
/* bytes: cumulative network bytes; t: monotonic seconds. */
void otz_rate_add(OtzRate *rate, long long bytes, double t);
/* The next sample is measured from here: the gap before it is not a slow sample. */
void otz_rate_rebaseline(OtzRate *rate, long long bytes, double t);
/* Bytes per second, or -1 before anything was measured. */
double otz_rate_value(const OtzRate *rate);
/* Latches once true, until a stall of 30 s or more starts the window over. */
int otz_rate_warm(OtzRate *rate, long long remaining);

/* The shown value: a real-time countdown, corrected toward the raw estimate
 * only at correction points (end of a burst, or 2 s of continuous flow). */
typedef struct {
  int has_shown, has_last, has_data;
  double shown, last_t, last_correction_t, last_data_t;
  double flow_start_t, raw_at_last_data;
  int run_open;
} OtzEtaDisplay;

void otz_eta_display_reset(OtzEtaDisplay *display);
/* fresh: new data or progress since the previous update. */
double otz_eta_display_update(OtzEtaDisplay *display, double raw, double t, int fresh);
/* The time until the next update is not counted down (a stall or a pause). */
void otz_eta_display_freeze(OtzEtaDisplay *display, double t);

typedef enum {
  OTZ_ETA_CALCULATING,
  OTZ_ETA_ESTIMATING,
  OTZ_ETA_STALLED, /* no bytes for 5 s: "waiting for the connection" */
  OTZ_ETA_PHASE,   /* a post-download step runs */
} OtzEtaStatus;

/* One per job. */
typedef struct {
  OtzRate rate, speed;
  OtzEtaDisplay display;
  int started, paused;
  long long last_net;
  double last_activity_t;
} OtzEta;

void otz_eta_init(OtzEta *eta);
/* One poll. net: network bytes so far; remaining: download bytes left; post:
 * seconds of the running step's rest and the planned steps; phase: a post step
 * runs (phase_fresh: its progress moved); paused: a known silent step. *shown
 * gets the seconds to show, or -1. */
OtzEtaStatus otz_eta_tick(OtzEta *eta, double t, long long net, long long remaining,
                          double post, int phase, int phase_fresh, int paused,
                          double *shown);
/* The displayed speed (the same rate with tau 3 s), 0 until a second of data. */
double otz_eta_speed(const OtzEta *eta);

/* Measured rates of post-download work, with conservative defaults until measured. */
typedef struct {
  double bytes[OTZ_WORK_KINDS], seconds[OTZ_WORK_KINDS];
  int kind, based;
  double last_t;
  long long last_done;
} OtzWorkRates;

void otz_work_init(OtzWorkRates *work);
/* done: bytes processed so far by the running step of this kind. */
void otz_work_sample(OtzWorkRates *work, OtzWorkKind kind, double now, long long done);
double otz_work_rate(const OtzWorkRates *work, OtzWorkKind kind);
double otz_work_seconds(const OtzWorkRates *work, long long copy_bytes,
                        long long hash_bytes);

/* Rounding of the shown value: hours/minutes/seconds, all 0 = "a few seconds". */
void otz_eta_round(double seconds, int *hours, int *minutes, int *secs);
