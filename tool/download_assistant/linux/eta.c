#include "eta.h"

#include <math.h>
#include <string.h>

#define RATE_TAU 8.0
#define SPEED_TAU 3.0
#define ISOLATED_STALL_SECONDS 2.0
#define FLOW_GAP_SECONDS 1.0
#define FLOW_SECONDS 2.0
#define MAX_CORRECTION_SECONDS 30.0

static const double default_rates[OTZ_WORK_KINDS] = {
    [OTZ_WORK_COPY] = 100e6,
    [OTZ_WORK_HASH] = 150e6,
};

static double max_d(double a, double b) { return a > b ? a : b; }
static double min_d(double a, double b) { return a < b ? a : b; }

/* ------------------------------------------------------------------ rate */

void otz_rate_init(OtzRate *rate, double tau) {
  memset(rate, 0, sizeof *rate);
  rate->tau = tau;
}

void otz_rate_rebaseline(OtzRate *rate, long long bytes, double t) {
  rate->has_last = 1;
  rate->last_t = t;
  rate->last_bytes = bytes;
}

void otz_rate_add(OtzRate *rate, long long bytes, double t) {
  if (!rate->has_last) {
    otz_rate_rebaseline(rate, bytes, t);
    return;
  }
  long long db = bytes - rate->last_bytes;
  if (db < 0) {
    otz_rate_rebaseline(rate, bytes, t);
    return;
  }
  if (db == 0) return;
  double gap = t - rate->last_t;
  if (gap < 0.05) return;
  if (gap >= OTZ_ETA_RESTART_SECONDS) {
    /* A new window starts with the returning data; this sample is only a base. */
    rate->sb = rate->st = 0;
    rate->warm_t = rate->warm_bytes = 0;
    rate->warm_n = rate->warmed = 0;
    rate->max_gap = 0;
    rate->has_stall_recovery = 0;
    rate->iso_deficit = 0;
    otz_rate_rebaseline(rate, bytes, t);
    return;
  }
  double dt = gap;
  if (gap >= OTZ_ETA_STALL_SECONDS) {
    /* A long silence that recurs (a proxy that delivers in bursts) is part of
     * the rate; a lone stall is not. */
    if (rate->has_stall_recovery &&
        t - rate->last_stall_recovery_t <= OTZ_ETA_RESTART_SECONDS) {
      /* The previous stall counted as lone (2 s): add the rest of its gap. */
      rate->st += rate->iso_deficit * exp(-(t - rate->last_stall_recovery_t) / rate->tau);
      rate->active += rate->iso_deficit;
      rate->warm_t += rate->iso_deficit;
      rate->iso_deficit = 0;
    } else {
      dt = ISOLATED_STALL_SECONDS;
      rate->iso_deficit = gap - ISOLATED_STALL_SECONDS;
    }
    rate->has_stall_recovery = 1;
    rate->last_stall_recovery_t = t;
  }
  rate->max_gap = max_d(rate->max_gap, gap);
  double d = exp(-dt / rate->tau);
  rate->sb = rate->sb * d + (double)db;
  rate->st = rate->st * d + dt;
  rate->active += dt;
  rate->session_bytes += (double)db;
  rate->warm_t += dt;
  rate->warm_bytes += (double)db;
  rate->warm_n++;
  rate->last_t = t;
  rate->last_bytes = bytes;
}

double otz_rate_value(const OtzRate *rate) {
  if (rate->st <= 0 || rate->active <= 0) return -1;
  double w = min_d(max_d(rate->active / 60, 0.5), 1.0);
  return w * (rate->sb / rate->st) + (1 - w) * (rate->session_bytes / rate->active);
}

int otz_rate_warm(OtzRate *rate, long long remaining) {
  /* A bursty stream waits for a few cycles; a later lone stall does not undo it. */
  double needed_t = max_d(3, min_d(15, 3 * rate->max_gap));
  if (rate->warm_t >= needed_t && rate->warm_n >= 3 &&
      rate->warm_bytes >= min_d(1048576, remaining * 0.01))
    rate->warmed = 1;
  return rate->warmed;
}

/* --------------------------------------------------------------- display */

void otz_eta_display_reset(OtzEtaDisplay *display) {
  display->has_shown = 0;
  display->has_last = 0;
  display->last_correction_t = 0;
  display->run_open = 0;
}

double otz_eta_display_update(OtzEtaDisplay *display, double raw, double t, int fresh) {
  int had_last = display->has_last;
  double last = display->last_t;
  display->has_last = 1;
  display->last_t = t;
  int had_data = display->has_data;
  double last_data = display->last_data_t;
  int has_target = display->run_open && had_data && t - last_data >= FLOW_GAP_SECONDS;
  double target = display->raw_at_last_data;
  if (has_target) display->run_open = 0;
  if (fresh) {
    if (!had_data || t - last_data >= FLOW_GAP_SECONDS) display->flow_start_t = t;
    display->has_data = 1;
    display->last_data_t = t;
    display->raw_at_last_data = raw;
    display->run_open = 1;
  }
  if (!display->has_shown || !had_last) {
    display->last_correction_t = t;
    display->has_shown = 1;
    return display->shown = raw;
  }
  double next = display->shown - (t - last);
  if (fresh && t - display->flow_start_t >= FLOW_SECONDS) {
    has_target = 1;
    target = raw;
  }
  if (has_target) {
    double cdt = min_d(t - display->last_correction_t, MAX_CORRECTION_SECONDS);
    display->last_correction_t = t;
    if (target < next * 0.5) {
      next = target;
    } else {
      double diff = target - next;
      double tau = fabs(diff) <= max_d(5, next * 0.10) ? 30 : diff < 0 ? 3 : 12;
      next += (1 - exp(-cdt / tau)) * diff;
    }
  }
  return display->shown = max_d(next, 0);
}

void otz_eta_display_freeze(OtzEtaDisplay *display, double t) {
  display->has_last = 1;
  display->last_t = t;
  display->run_open = 0;
}

/* ------------------------------------------------------------------- job */

void otz_eta_init(OtzEta *eta) {
  memset(eta, 0, sizeof *eta);
  otz_rate_init(&eta->rate, RATE_TAU);
  otz_rate_init(&eta->speed, SPEED_TAU);
  eta->paused = 1;
}

OtzEtaStatus otz_eta_tick(OtzEta *eta, double t, long long net, long long remaining,
                          double post, int phase, int phase_fresh, int paused,
                          double *shown) {
  int fresh = phase && phase_fresh;
  *shown = -1;
  if (phase || paused) {
    eta->paused = 1;
  } else if (net != eta->last_net) {
    if (eta->paused || net < eta->last_net) {
      /* The first bytes after a pause are only a base: no rate, no stall before them. */
      eta->paused = 0;
      eta->started = 1;
      otz_rate_rebaseline(&eta->rate, net, t);
      otz_rate_rebaseline(&eta->speed, net, t);
    } else {
      otz_rate_add(&eta->rate, net, t);
      otz_rate_add(&eta->speed, net, t);
    }
    fresh = 1;
    eta->last_net = net;
    eta->last_activity_t = t;
  }

  if (!eta->started && !phase) {
    otz_eta_display_reset(&eta->display);
    return OTZ_ETA_CALCULATING;
  }
  if (!phase && !eta->paused && remaining > 0) {
    double silence = t - eta->last_activity_t;
    if (silence >= OTZ_ETA_STALL_SECONDS) {
      otz_eta_display_freeze(&eta->display, t);
      if (silence >= OTZ_ETA_RESTART_SECONDS) otz_eta_display_reset(&eta->display);
      return OTZ_ETA_STALLED;
    }
  }
  double raw = -1, rate = otz_rate_value(&eta->rate);
  if (remaining <= 0)
    raw = 0;
  else if (rate > 0 && otz_rate_warm(&eta->rate, remaining))
    raw = remaining / rate;
  OtzEtaStatus status = phase ? OTZ_ETA_PHASE : OTZ_ETA_ESTIMATING;
  if (raw < 0) {
    otz_eta_display_reset(&eta->display);
    return phase ? OTZ_ETA_PHASE : OTZ_ETA_CALCULATING;
  }
  raw += post;
  /* A known pause that is not an estimated step: the display holds, like a stall. */
  if (eta->paused && !phase && eta->display.has_shown) {
    otz_eta_display_freeze(&eta->display, t);
    *shown = eta->display.shown;
  } else {
    *shown = otz_eta_display_update(&eta->display, raw, t, fresh);
  }
  return status;
}

double otz_eta_speed(const OtzEta *eta) {
  if (eta->speed.active < 1) return 0;
  double speed = otz_rate_value(&eta->speed);
  return speed > 0 ? speed : 0;
}

/* ------------------------------------------------------------ post steps */

void otz_work_init(OtzWorkRates *work) { memset(work, 0, sizeof *work); }

void otz_work_sample(OtzWorkRates *work, OtzWorkKind kind, double now, long long done) {
  if (work->based && work->kind == (int)kind && done >= work->last_done) {
    work->bytes[kind] += (double)(done - work->last_done);
    work->seconds[kind] += now - work->last_t;
  }
  work->based = 1;
  work->kind = kind;
  work->last_t = now;
  work->last_done = done;
}

double otz_work_rate(const OtzWorkRates *work, OtzWorkKind kind) {
  /* Under a second of work says little: a hard link or a cached page. */
  if (work->seconds[kind] >= 1 && work->bytes[kind] > 0)
    return work->bytes[kind] / work->seconds[kind];
  return default_rates[kind];
}

double otz_work_seconds(const OtzWorkRates *work, long long copy_bytes,
                        long long hash_bytes) {
  double seconds = 0;
  if (copy_bytes > 0) seconds += copy_bytes / otz_work_rate(work, OTZ_WORK_COPY);
  if (hash_bytes > 0) seconds += hash_bytes / otz_work_rate(work, OTZ_WORK_HASH);
  return seconds;
}

void otz_eta_round(double seconds, int *hours, int *minutes, int *secs) {
  *hours = *minutes = *secs = 0;
  if (seconds < 5) return;
  if (seconds < 60) {
    int n = (int)lround(seconds / 5) * 5;
    if (n < 60) {
      *secs = n;
      return;
    }
    seconds = 60;
  }
  if (seconds < 600) {
    int total = (int)lround(seconds / 10) * 10;
    if (total < 600) {
      *minutes = total / 60;
      *secs = total % 60;
      return;
    }
    seconds = 600;
  }
  if (seconds < 3600) {
    int m = (int)lround(seconds / 60);
    if (m < 60) {
      *minutes = m;
      return;
    }
    seconds = 3600;
  }
  long long h = (long long)(seconds / 3600);
  int m = (int)lround((seconds - h * 3600.0) / 300) * 5;
  if (m == 60) {
    h++;
    m = 0;
  }
  *hours = (int)h;
  *minutes = m;
}
