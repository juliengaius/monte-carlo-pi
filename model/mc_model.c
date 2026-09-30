/*
 * mc_model.c - bit-exact C reference model of the Monte Carlo pi accelerator.
 *
 * Mirrors the RTL datapath:
 *   lfsr32.v          32-bit Fibonacci LFSR, taps [31,21,1,0], one shift per clock
 *   unitizer_uq16.v   top 16 bits of each LFSR -> UQ0.16 coordinate in [0,1)
 *   hit_kernel_*.v    inside if x^2 + y^2 <= 1.0  (1.0 = 2^32 at UQ0.32)
 *   mc_counters.v     32-bit hit and total counters
 *   pi_divider.v      pi_q = ((hits << 2) << 29) / total in a 61-bit datapath (Q3.29)
 *
 * Timing: the LFSRs free-run every clock, so a sample's random numbers depend
 * on exactly which clock edge the unitizer latches them. From the FSMs:
 *   control_fsm sees space_pulse at cycle S          -> SPAWN_KICK at S+1
 *   point_fsm   GET_RANDOM (unit_load) at S+2        -> first sample latched at cycle S+2
 *   each point: GET_RANDOM, COMPUTE_HIT, UPDATE_CNT, 256 DRAW cycles, sprite DONE,
 *               point DONE, then control re-KICKs    -> next sample 262 cycles later
 * Cycle 0 is the first rising edge after reset is released; the LFSR holds its
 * seed during cycle 0, so the state latched at cycle c is the seed stepped c times.
 *
 * Build:  cc -O2 -o mc_model mc_model.c
 * Usage:
 *   mc_model dump <schedule.txt> <samples.csv>
 *       schedule: one line per batch, "<space_cycle> <batch_size>"
 *       writes every sample plus final hits/total/pi_q, for comparison with RTL
 *   mc_model converge <num_samples> [<curve.csv>]
 *       one continuous batch from reset; reports the pi estimate at checkpoints
 *   mc_model period
 *       checks the LFSR period is 2^32 - 1 and finds the phase offset between
 *       the X and Y LFSRs (takes a few seconds)
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define SEED_X 0xF001AB32u
#define SEED_Y 0xF0005465u

#define FIRST_SAMPLE_DELAY 2u    /* space_pulse cycle -> first unit_load */
#define CYCLES_PER_SAMPLE  262u  /* unit_load to next unit_load within a batch */

#define FBITS 29
#define DIV_WIDTH 61             /* W + FBITS = 32 + 29 */

/* ---------------- datapath ---------------- */

static uint32_t lfsr_step(uint32_t s)
{
    uint32_t new_bit = ((s >> 31) ^ (s >> 21) ^ (s >> 1) ^ s) & 1u;
    return (s << 1) | new_bit;
}

static uint16_t unitize(uint32_t s)           /* UQ0.16: keep the top 16 bits */
{
    return (uint16_t)(s >> 16);
}

static int hit_kernel(uint16_t x, uint16_t y) /* x^2 + y^2 <= 1.0 */
{
    uint64_t sum = (uint64_t)x * x + (uint64_t)y * y;
    return sum <= (1ull << 32);
}

static uint64_t pi_divider(uint32_t hits, uint32_t total)
{
    const uint64_t mask = (1ull << DIV_WIDTH) - 1;
    uint64_t numerator = (((uint64_t)hits << 2) << FBITS) & mask; /* wraps like the RTL register */
    uint64_t denom = (total == 0) ? 1 : total;
    return numerator / denom;
}

static double q329_to_double(uint64_t q)
{
    return (double)q / (double)(1u << FBITS);
}

/* ---------------- free-running LFSR pair ---------------- */

typedef struct {
    uint32_t x, y;     /* LFSR states during cycle `cycle` */
    uint64_t cycle;
} lfsr_pair;

static void lfsr_reset(lfsr_pair *p)
{
    p->x = SEED_X;
    p->y = SEED_Y;
    p->cycle = 0;
}

static void lfsr_advance_to(lfsr_pair *p, uint64_t cycle)
{
    if (cycle < p->cycle) {
        fprintf(stderr, "error: schedule goes backwards in time (cycle %llu)\n",
                (unsigned long long)cycle);
        exit(1);
    }
    while (p->cycle < cycle) {
        p->x = lfsr_step(p->x);
        p->y = lfsr_step(p->y);
        p->cycle++;
    }
}

/* ---------------- modes ---------------- */

static int mode_dump(const char *schedule_path, const char *out_path)
{
    FILE *sched = fopen(schedule_path, "r");
    FILE *out = fopen(out_path, "w");
    if (!sched || !out) { perror("open"); return 1; }

    lfsr_pair lfsr;
    lfsr_reset(&lfsr);
    uint32_t hits = 0, total = 0, idx = 0;
    unsigned long long space_cycle, batch;

    fprintf(out, "idx,cycle,x,y,hit\n");
    while (fscanf(sched, "%llu %llu", &space_cycle, &batch) == 2) {
        for (uint64_t k = 0; k < batch; k++) {
            uint64_t c = space_cycle + FIRST_SAMPLE_DELAY + k * CYCLES_PER_SAMPLE;
            lfsr_advance_to(&lfsr, c);
            uint16_t x = unitize(lfsr.x), y = unitize(lfsr.y);
            int hit = hit_kernel(x, y);
            total++;
            hits += hit;
            fprintf(out, "%u,%llu,%u,%u,%d\n", idx++, (unsigned long long)c, x, y, hit);
        }
    }
    uint64_t pi_q = pi_divider(hits, total);
    fprintf(out, "final,hits=%u,total=%u,pi_q=%llu\n", hits, total, (unsigned long long)pi_q);
    fclose(sched);
    fclose(out);
    printf("model: %u samples, hits=%u, pi=%.9f\n", total, hits, q329_to_double(pi_q));
    return 0;
}

static int mode_converge(uint64_t n, const char *curve_path)
{
    FILE *curve = curve_path ? fopen(curve_path, "w") : NULL;
    if (curve_path && !curve) { perror("open"); return 1; }
    if (curve) fprintf(curve, "samples,hits,pi_estimate,abs_rel_error_pct\n");

    lfsr_pair lfsr;
    lfsr_reset(&lfsr);
    uint32_t hits = 0;
    uint64_t next_checkpoint = 10;

    /* running sums for the Pearson correlation between x and y */
    double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;

    const uint64_t space_cycle = 0;  /* continuous batch started right after reset */
    for (uint64_t k = 0; k < n; k++) {
        lfsr_advance_to(&lfsr, space_cycle + FIRST_SAMPLE_DELAY + k * CYCLES_PER_SAMPLE);
        uint16_t x = unitize(lfsr.x), y = unitize(lfsr.y);
        hits += hit_kernel(x, y);

        double fx = x / 65536.0, fy = y / 65536.0;
        sx += fx; sy += fy; sxx += fx * fx; syy += fy * fy; sxy += fx * fy;

        uint64_t total = k + 1;
        int last = (total == n);
        if (total == next_checkpoint || last) {
            double pi = q329_to_double(pi_divider(hits, (uint32_t)total));
            double err = fabs(pi - M_PI) / M_PI * 100.0;
            if (curve)
                fprintf(curve, "%llu,%u,%.9f,%.6f\n", (unsigned long long)total, hits, pi, err);
            if (total == next_checkpoint)
                next_checkpoint = (uint64_t)ceil(next_checkpoint * 1.25893); /* 10 points per decade */
        }
    }

    double pi = q329_to_double(pi_divider(hits, (uint32_t)n));
    double err = fabs(pi - M_PI) / M_PI * 100.0;
    double p = M_PI / 4.0;
    double expected_sd = 4.0 * sqrt(p * (1 - p) / (double)n) / M_PI * 100.0;
    double N = (double)n;
    double corr = (sxy / N - (sx / N) * (sy / N)) /
                  sqrt((sxx / N - (sx / N) * (sx / N)) * (syy / N - (sy / N) * (sy / N)));

    printf("samples            : %llu\n", (unsigned long long)n);
    printf("hits               : %u\n", hits);
    printf("pi estimate        : %.9f\n", pi);
    printf("relative error     : %.4f%%\n", err);
    printf("expected 1-sigma   : %.4f%%  (binomial sampling noise at this N)\n", expected_sd);
    printf("x/y correlation    : %+.6f\n", corr);
    if (curve) fclose(curve);
    return 0;
}

static int mode_period(void)
{
    /* Walk the sequence from SEED_X until it returns; note when it hits SEED_Y. */
    uint32_t s = SEED_X;
    uint64_t steps = 0, offset_y = 0;
    int found_y = 0;
    do {
        s = lfsr_step(s);
        steps++;
        if (!found_y && s == SEED_Y) { offset_y = steps; found_y = 1; }
    } while (s != SEED_X && steps <= 0xFFFFFFFFull);

    printf("LFSR period        : %llu (2^32 - 1 = %llu) -> %s\n",
           (unsigned long long)steps, 0xFFFFFFFFull,
           steps == 0xFFFFFFFFull ? "maximal length" : "NOT maximal");
    if (found_y)
        printf("Y sequence = X sequence shifted by %llu steps\n", (unsigned long long)offset_y);
    else
        printf("SEED_Y not on SEED_X's cycle\n");
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 4 && strcmp(argv[1], "dump") == 0)
        return mode_dump(argv[2], argv[3]);
    if (argc >= 3 && strcmp(argv[1], "converge") == 0)
        return mode_converge(strtoull(argv[2], NULL, 10), argc >= 4 ? argv[3] : NULL);
    if (argc >= 2 && strcmp(argv[1], "period") == 0)
        return mode_period();

    fprintf(stderr,
            "usage: %s dump <schedule.txt> <samples.csv>\n"
            "       %s converge <num_samples> [<curve.csv>]\n"
            "       %s period\n", argv[0], argv[0], argv[0]);
    return 2;
}
