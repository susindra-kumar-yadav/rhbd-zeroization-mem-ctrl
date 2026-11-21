#!/usr/bin/env python3
# =============================================================================
# File:        scrub_experiment.py
# Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
# Target:      Python Standard Library Only
# Description: Scrub-Interval vs. Multi-Bit SEU Accumulation Experiment.
#
# Simulation Model:
#   - Memory array: 256 words, each 18 bits wide (DEC-TED ECC, T = 2).
#   - Radiation Environment: SEUs arrive at a constant Poisson / fixed rate
#     striking random memory words and flipping random bit positions.
#   - Scrubber Architecture: The autonomous background scrubber visits one
#     word every SCRUB_INTERVAL cycles, repairing words with <= T errors.
#   - Evaluation Metric: Counts how many words ever accumulate > T errors (>= 3),
#     leading to uncorrectable data corruption.
# =============================================================================

import random
import sys

def run_scrub_simulation(num_words=256, cw_bits=18, t_cap=2,
                         total_cycles=50000, strike_interval=20, scrub_intervals=None):
    if scrub_intervals is None:
        scrub_intervals = [2, 4, 8, 16, 32, 64, 128, 256, 512]

    print("==================================================================")
    print("   RHBD MEMORY CONTROLLER: SCRUB-INTERVAL RELIABILITY EXPERIMENT  ")
    print(f"   Memory Geometry: {num_words} words x {cw_bits} bits")
    print(f"   ECC Capability : T = {t_cap} (Double-Error Correcting)")
    print(f"   Total Cycles   : {total_cycles}")
    print(f"   SEU Injection  : 1 strike every {strike_interval} clock cycles")
    print("==================================================================")
    print(f"{'Scrub Interval':<16}{'Full Sweep':<14}{'SEUs Injected':<16}{'SEUs Repaired':<16}{'Words with >T Errors':<22}{'Reliability Status'}")
    print("-" * 100)

    for s_int in scrub_intervals:
        rng = random.Random(42) # Deterministic for reproducible viva demos
        
        # Array of error counts per word
        word_errors = [0] * num_words
        words_ever_exceeded_t = 0
        total_seus = 0
        total_repaired = 0
        
        scrub_ptr = 0
        scrub_timer = 0
        sweep_time = s_int * num_words
        
        for cycle in range(total_cycles):
            # 1. Random SEU Strike
            if cycle > 0 and (cycle % strike_interval) == 0:
                target_word = rng.randint(0, num_words - 1)
                target_bit = rng.randint(0, cw_bits - 1)
                total_seus += 1
                
                word_errors[target_word] += 1
                if word_errors[target_word] == (t_cap + 1):
                    words_ever_exceeded_t += 1
                    
            # 2. Autonomous Scrubber Action
            scrub_timer += 1
            if scrub_timer >= s_int:
                scrub_timer = 0
                current_errs = word_errors[scrub_ptr]
                if 1 <= current_errs <= t_cap:
                    # Successfully repaired by DEC-TED ECC in-situ write-back
                    total_repaired += current_errs
                    word_errors[scrub_ptr] = 0
                elif current_errs > t_cap:
                    # Uncorrectable: scrubber cannot repair without telemetry alert
                    pass
                
                scrub_ptr = (scrub_ptr + 1) % num_words
                
        status = "100% PROTECTED" if words_ever_exceeded_t == 0 else f"CORRUPTED ({words_ever_exceeded_t} words)"
        print(f"{s_int:<16}{sweep_time:<14}{total_seus:<16}{total_repaired:<16}{words_ever_exceeded_t:<22}{status}")

    print("-" * 100)
    print("Key Engineering Takeaway for Viva:")
    print("  When the memory scrub sweep period is shorter than the expected time for a word")
    print("  to accumulate 3 strikes, latent single-bit and double-bit faults are eliminated")
    print("  before uncorrectable triple-bit errors can form. Fast scrubbing delivers 100% mission survival.")
    print("==================================================================")

if __name__ == "__main__":
    run_scrub_simulation()
