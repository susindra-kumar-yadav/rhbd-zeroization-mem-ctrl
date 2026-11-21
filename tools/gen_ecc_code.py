#!/usr/bin/env python3
# =============================================================================
# File:        gen_ecc_code.py
# Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
# Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
# Standards:   Verilog-2001 (Pure combinational XOR encoders & syndrome decoders)
# Description: Automated Systematic Linear Binary ECC Generator (Standard Library Only).
#              Searches for the shortest systematic code for DATA_W data bits
#              with minimum distance >= 2T+2 (DEC-TED: corrects T, detects T+1).
#              If 2T+2 is not attainable within reasonable check bits, falls
#              back to 2T+1 (DEC).
#
# Generates:
#   1) Memory ECC (DATA_W=8, T=2 DEC-TED, CW=18, CHK=10, d_min=6):
#      - rtl/ecc_params.vh
#      - rtl/ecc_enc.v
#      - rtl/ecc_dec.v
#   2) FSM State ECC (DATA_W=3, Parameterized T_STATE=1 and T_STATE=2, default T_STATE=2):
#      - T_STATE=2: CW=11, CHK=8, d_min=6, 67 table entries (DEC-TED)
#      - T_STATE=1: CW=7,  CHK=4, d_min=4, 8 table entries  (SECDED)
#      - rtl/state_ecc_params.vh
#      - rtl/state_ecc_enc.v
#      - rtl/state_ecc_dec.v
# =============================================================================

import sys
import os
import argparse
import random

def parse_args():
    parser = argparse.ArgumentParser(description="Generate Verilog-2001 ECC Encoders and Decoders")
    parser.add_argument("--data_w", type=int, default=8, help="Number of information data bits (default: 8)")
    parser.add_argument("--t", type=int, default=2, help="Error correction capability in bits (default: 2)")
    parser.add_argument("--t_state", type=int, default=2, choices=[1, 2], help="Per-copy FSM State ECC strength (1=SECDED, 2=DEC-TED, default: 2)")
    parser.add_argument("--out_dir", type=str, default="rtl", help="Output directory for generated Verilog files")
    parser.add_argument("--target", type=str, default="all", choices=["all", "mem", "state", "custom"],
                        help="Target ECC generation: 'mem' (DATA_W=8, T=2), 'state' (DATA_W=3, T=T_STATE), or 'all' (both)")
    parser.add_argument("--prefix", type=str, default="", help="Prefix for file and module names (e.g., 'state_')")

    args, unknown = parser.parse_known_args()
    if unknown and len(unknown) >= 1:
        try:
            args.data_w = int(unknown[0])
            if len(unknown) >= 2:
                args.t = int(unknown[1])
            args.target = "state" if args.data_w == 3 else "custom"
        except ValueError:
            pass
    elif "--data_w" in sys.argv and "--target" not in sys.argv:
        args.target = "state" if args.data_w == 3 else "custom"
    return args

def compute_min_distance(k, chk, P):
    """Brute force verification of minimum distance over all 2^k - 1 non-zero words."""
    min_d = 999
    weight_hist = {}
    for d in range(1, 1 << k):
        p_val = 0
        for i in range(k):
            if (d >> i) & 1:
                p_val ^= P[i]
        w = bin(d).count('1') + bin(p_val).count('1')
        weight_hist[w] = weight_hist.get(w, 0) + 1
        if w < min_d:
            min_d = w
    return min_d, weight_hist

def find_ecc_matrix(k, t):
    """
    Searches for the shortest systematic generator matrix G = [I_k | P]
    achieving minimum distance d_target = 2T + 2 (DEC-TED).
    If not found, falls back to 2T + 1 (DEC).
    """
    d_target = 2 * t + 2
    d_fallback = 2 * t + 1
    
    # Pre-calculated optimal matrices for canonical parameter sets
    KNOWN_OPTIMAL = {
        (8, 2): (10, [433, 911, 761, 110, 666, 61, 871, 453]),  # [18, 8, 6] DEC-TED
        (8, 1): (5,  [19, 21, 22, 25, 26, 28, 13, 11]),          # [13, 8, 4] SECDED
        (3, 2): (8,  [31, 103, 171]),                             # [11, 3, 6] DEC-TED (67 table entries)
        (3, 1): (4,  [7, 13, 11])                                 # [7, 3, 4] SECDED (8 table entries)
    }
    
    if (k, t) in KNOWN_OPTIMAL:
        chk, P = KNOWN_OPTIMAL[(k, t)]
        real_d, hist = compute_min_distance(k, chk, P)
        return chk, P, real_d, hist
    
    # General Search: start from minimum theoretical check bits
    start_chk = d_target - 1
    max_chk = start_chk + 12
    
    print(f"[*] Searching for optimal linear code: k={k}, target d>={d_target} (DEC-TED)...")
    for chk in range(start_chk, max_chk + 1):
        allowed_weights = [w for w in range(d_target - 1, chk + 1) if (w + 1) % 2 == 0] if (d_target % 2 == 0) else range(d_target - 1, chk + 1)
        valid_rows = [val for val in range(1, 1 << chk) if bin(val).count('1') in allowed_weights]
        
        if len(valid_rows) < k:
            continue
            
        for trial in range(30000):
            rng = random.Random(trial + chk * 100000)
            P = rng.sample(valid_rows, k)
            
            min_d = 999
            for d in range(1, 1 << k):
                p_val = 0
                for i in range(k):
                    if (d >> i) & 1:
                        p_val ^= P[i]
                w = bin(d).count('1') + bin(p_val).count('1')
                if w < min_d:
                    min_d = w
                    if min_d < d_target:
                        break
            if min_d >= d_target:
                real_d, hist = compute_min_distance(k, chk, P)
                print(f"[+] Found optimal code with d={real_d} >= {d_target} at CHK={chk} (CW={k+chk})")
                return chk, P, real_d, hist

    print(f"[!] Warning: d>={d_target} not found within search limit. Falling back to d>={d_fallback}...")
    for chk in range(d_fallback - 1, max_chk + 1):
        valid_rows = [val for val in range(1, 1 << chk) if bin(val).count('1') >= d_fallback - 1]
        for trial in range(30000):
            rng = random.Random(trial + chk * 100000)
            P = rng.sample(valid_rows, k)
            min_d = 999
            for d in range(1, 1 << k):
                p_val = 0
                for i in range(k):
                    if (d >> i) & 1:
                        p_val ^= P[i]
                w = bin(d).count('1') + bin(p_val).count('1')
                if w < min_d:
                    min_d = w
                    if min_d < d_fallback:
                        break
            if min_d >= d_fallback:
                real_d, hist = compute_min_distance(k, chk, P)
                return chk, P, real_d, hist
                
    raise RuntimeError(f"Could not construct linear code for k={k}, t={t}")

def build_syndromes_map(k, chk, n, t, P):
    """Constructs syndrome -> (weight, pattern) lookup table for all errors of weight <= t."""
    syndromes_map = {}
    syndromes_map[0] = (0, 0)
    
    # Weight 1 errors
    for bit in range(n):
        pat = 1 << bit
        ed = pat >> chk
        ep = pat & ((1 << chk) - 1)
        s = 0
        for b in range(k):
            if (ed >> b) & 1:
                s ^= P[b]
        s ^= ep
        if s in syndromes_map:
            raise ValueError(f"Syndrome collision at weight 1! s={s}")
        syndromes_map[s] = (1, pat)
        
    # Weight 2 errors
    if t >= 2:
        for b1 in range(n):
            for b2 in range(b1 + 1, n):
                pat = (1 << b1) | (1 << b2)
                ed = pat >> chk
                ep = pat & ((1 << chk) - 1)
                s = 0
                for b in range(k):
                    if (ed >> b) & 1:
                        s ^= P[b]
                s ^= ep
                if s in syndromes_map:
                    raise ValueError(f"Syndrome collision at weight 2! s={s}")
                syndromes_map[s] = (2, pat)
                
    return syndromes_map

def generate_header(out_dir, k, chk, n, t, d_min, prefix=""):
    """Generates rtl/{prefix}ecc_params.vh"""
    filename = f"{prefix}ecc_params.vh"
    header_path = os.path.join(out_dir, filename)
    guard = f"{prefix.upper()}ECC_PARAMS_VH"
    pfx_upper = prefix.upper()
    
    desc = f"FSM 3-Bit State Register ECC Protection (T={t})" if k == 3 else f"Double-Error-Correcting (DEC-TED, T={t}) Memory ECC"
    
    content = f"""`timescale 1ns / 1ps
// =============================================================================
// File:        {filename}
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Global Parameters for {desc}.
//
// Parameters:
//   DATA_W   = {k}  (Information payload bits)
//   CHK_W    = {chk} (Parity check bits)
//   CW_W     = {n} (Total codeword width)
//   T_ERR    = {t}  (Maximum correctable bit errors)
//   D_MIN    = {d_min}  (Minimum Hamming distance)
// =============================================================================

`ifndef {guard}
`define {guard}

parameter {pfx_upper}ECC_DATA_W = {k};
parameter {pfx_upper}ECC_CHK_W  = {chk};
parameter {pfx_upper}ECC_CW_W   = {n};
parameter {pfx_upper}ECC_T      = {t};
parameter {pfx_upper}ECC_DMIN   = {d_min};

`endif // {guard}
"""
    with open(header_path, "w") as f:
        f.write(content)
    print(f"[*] Generated: {header_path}")

def generate_encoder(out_dir, k, chk, n, P, prefix="", t=2):
    """Generates rtl/{prefix}ecc_enc.v"""
    mod_name = f"{prefix}ecc_enc"
    enc_path = os.path.join(out_dir, f"{mod_name}.v")
    
    parity_eqs = []
    for p in range(chk):
        covering_data = [i for i in range(k) if ((P[i] >> p) & 1)]
        terms = " ^ ".join([f"data[{i}]" for i in covering_data])
        parity_eqs.append(f"    wire p{p} = {terms};")
    
    assign_code = []
    for p in range(chk):
        assign_code.append(f"    assign code[{p}] = p{p};")
    for d in range(k):
        assign_code.append(f"    assign code[{chk + d}] = data[{d}];")
        
    parity_eqs_str = "\n".join(parity_eqs)
    assign_code_str = "\n".join(assign_code)
    
    desc = f"State Codeword Encoder (T={t})" if k == 3 else "Pure Combinational Systematic Linear ECC Encoder"
    
    content = f"""`timescale 1ns / 1ps
// =============================================================================
// File:        {mod_name}.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: {desc}.
//
// Parameters & Geometry:
//   - DATA_W = {k} bits (payload)
//   - CHK_W  = {chk} bits (parity check bits)
//   - CW_W   = {n} bits (total codeword width)
//
// Codeword Layout (Systematic Form):
//   - code[{n-1}:{chk}] : Data bits payload (data[{k-1}:0])
//   - code[{chk-1}:0]  : Parity check bits (parity[{chk-1}:0])
//
// Key Mathematical Property:
//   data = {k}'h00 -> code = {n}'h0 (Essential for secure zeroization / clean reset).
// =============================================================================

module {mod_name} #(
    parameter DATA_W = {k},
    parameter CHK_W  = {chk},
    parameter CW_W   = {n}
)(
    input  wire [DATA_W-1:0] data,
    output wire [CW_W-1:0]   code
);

    // -------------------------------------------------------------------------
    // Parity Generation Logic (Combinational XOR Trees)
    // -------------------------------------------------------------------------
{parity_eqs_str}

    // -------------------------------------------------------------------------
    // Codeword Assembly: Systematic concatenation {{data, parity}}
    // -------------------------------------------------------------------------
{assign_code_str}

endmodule
"""
    with open(enc_path, "w") as f:
        f.write(content)
    print(f"[*] Generated: {enc_path}")

def generate_decoder(out_dir, k, chk, n, t, P, prefix=""):
    """Generates rtl/{prefix}ecc_dec.v"""
    mod_name = f"{prefix}ecc_dec"
    dec_path = os.path.join(out_dir, f"{mod_name}.v")
    
    syn_eqs = []
    for p in range(chk):
        covering_data = [i for i in range(k) if ((P[i] >> p) & 1)]
        terms = " ^ ".join([f"code[{chk + i}]" for i in covering_data])
        syn_eqs.append(f"    assign syn[{p}] = ({terms}) ^ code[{p}];")
    syn_eqs_str = "\n".join(syn_eqs)
    
    syndromes_map = build_syndromes_map(k, chk, n, t, P)
    case_entries = []
    sorted_syns = sorted(syndromes_map.keys(), key=lambda s: (syndromes_map[s][0], s))
    
    for s in sorted_syns:
        wt, pat = syndromes_map[s]
        case_entries.append(
            f"            {chk}'d{s}: begin\n"
            f"                err_pattern = {n}'b{pat:0{n}b};\n"
            f"                err_weight  = 2'd{wt};\n"
            f"                uncorr      = 1'b0;\n"
            f"            end"
        )
    case_entries_str = "\n".join(case_entries)
    
    desc = f"State Codeword Decoder (T={t})" if k == 3 else "Pure Combinational Systematic Linear ECC Decoder"
    
    content = f"""`timescale 1ns / 1ps
// =============================================================================
// File:        {mod_name}.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: {desc}.
//
// Capabilities:
//   - T = {t} (Corrects up to {t} bit flips anywhere in the {n}-bit stored word)
//   - Case-statement lookup table maps every correctable syndrome to its unique
//     error pattern. Any unlisted syndrome is flagged uncorrectable.
//
// Ports:
//   - code           : Raw codeword ({n}-bit)
//   - data_corrected : Corrected payload ({k}-bit)
//   - code_corrected : Corrected full codeword ({n}-bit)
//   - error_weight   : Number of bit errors identified (0..{t})
//   - uncorrectable  : High when an uncorrectable multi-bit fault is detected
//   - single_err     : Pulses high if exactly 1 bit error was corrected
//   - double_err     : Pulses high if exactly 2 bit errors were corrected
//   - corrected_err  : High if any correctable error (1..{t}) was repaired
//   - syndrome       : Raw {chk}-bit parity syndrome
// =============================================================================

module {mod_name} #(
    parameter DATA_W = {k},
    parameter CHK_W  = {chk},
    parameter CW_W   = {n},
    parameter T_ERR  = {t}
)(
    input  wire [CW_W-1:0]   code,
    output wire [DATA_W-1:0] data_corrected,
    output wire [CW_W-1:0]   code_corrected,
    output wire [1:0]        error_weight,
    output wire              uncorrectable,
    output wire              single_err,
    output wire              double_err,
    output wire              corrected_err,
    output wire [CHK_W-1:0]  syndrome
);

    // -------------------------------------------------------------------------
    // 1. Syndrome Calculation
    // -------------------------------------------------------------------------
    wire [CHK_W-1:0] syn;
{syn_eqs_str}

    assign syndrome = syn;

    // -------------------------------------------------------------------------
    // 2. Syndrome Lookup Table for Error Pattern & Weight
    // -------------------------------------------------------------------------
    reg [CW_W-1:0] err_pattern;
    reg [1:0]      err_weight;
    reg            uncorr;

    always @(*) begin
        case (syn)
{case_entries_str}
            default: begin
                err_pattern = {n}'d0;
                err_weight  = 2'd0;
                uncorr      = 1'b1;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // 3. Error Correction & Output Decoding
    // -------------------------------------------------------------------------
    wire [CW_W-1:0] corrected_codeword = code ^ err_pattern;

    assign code_corrected = corrected_codeword;
    assign data_corrected = corrected_codeword[CW_W-1:CHK_W];
    assign error_weight   = err_weight;
    assign uncorrectable  = uncorr;
    assign single_err     = (err_weight == 2'd1);
    assign double_err     = (err_weight == 2'd2);
    assign corrected_err  = (err_weight != 2'd0);

endmodule
"""
    with open(dec_path, "w") as f:
        f.write(content)
    print(f"[*] Generated: {dec_path}")
    return len(syndromes_map)

def generate_unified_state_ecc(out_dir):
    """
    Generates unified state_ecc_enc.v and state_ecc_dec.v that dynamically support
    BOTH T_STATE = 1 (SECDED [7,3,4]) and T_STATE = 2 (DEC-TED [11,3,6]) via
    Verilog-2001 generate blocks. Default is T_STATE = 2.
    Also generates rtl/state_ecc_params.vh.
    """
    # 1. state_ecc_params.vh
    params_path = os.path.join(out_dir, "state_ecc_params.vh")
    params_content = """`timescale 1ns / 1ps
// =============================================================================
// File:        state_ecc_params.vh
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Global Parameters for FSM State Register ECC Protection.
//              Supports both T_STATE = 1 (SECDED) and T_STATE = 2 (DEC-TED).
// =============================================================================

`ifndef STATE_ECC_PARAMS_VH
`define STATE_ECC_PARAMS_VH

// Default Configuration: T_STATE = 2 (DEC-TED [11, 3, 6])
parameter STATE_ECC_DATA_W    = 3;
parameter STATE_ECC_DEFAULT_T = 2;
parameter STATE_ECC_T2_CHK_W  = 8;
parameter STATE_ECC_T2_CW_W   = 11;
parameter STATE_ECC_T2_DMIN   = 6;
parameter STATE_ECC_T2_TABLE  = 67;

// Alternate Configuration: T_STATE = 1 (SECDED [7, 3, 4])
parameter STATE_ECC_T1_CHK_W  = 4;
parameter STATE_ECC_T1_CW_W   = 7;
parameter STATE_ECC_T1_DMIN   = 4;
parameter STATE_ECC_T1_TABLE  = 8;

`endif // STATE_ECC_PARAMS_VH
"""
    with open(params_path, "w") as f:
        f.write(params_content)
    print(f"[*] Generated: {params_path}")

    # 2. state_ecc_enc.v
    enc_path = os.path.join(out_dir, "state_ecc_enc.v")
    enc_content = """`timescale 1ns / 1ps
// =============================================================================
// File:        state_ecc_enc.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Parameterized Combinational FSM State Register ECC Encoder.
//              Supports both:
//                - T_ERR = 2 (default): DEC-TED [11, 3, 6] (CHK=8, CW=11)
//                - T_ERR = 1          : SECDED  [7, 3, 4]  (CHK=4, CW=7)
//
// Key Mathematical Property:
//   data = 3'b000 (ST_IDLE) -> code = 0 (clean reset & state self-healing).
// =============================================================================

module state_ecc_enc #(
    parameter DATA_W = 3,
    parameter T_ERR  = 2,
    parameter CHK_W  = (T_ERR == 1) ? 4 : 8,
    parameter CW_W   = DATA_W + CHK_W
)(
    input  wire [DATA_W-1:0] data,
    output wire [CW_W-1:0]   code
);

    generate
        if (CHK_W == 4 || T_ERR == 1) begin : gen_t1_secded
            // SECDED [7,3,4]: P = [7, 13, 11]
            // p0 = d0 ^ d1 ^ d2
            // p1 = d0 ^ d2
            // p2 = d0 ^ d1
            // p3 = d1 ^ d2
            wire p0 = data[0] ^ data[1] ^ data[2];
            wire p1 = data[0] ^ data[2];
            wire p2 = data[0] ^ data[1];
            wire p3 = data[1] ^ data[2];
            assign code = {data, p3, p2, p1, p0};
        end else begin : gen_t2_dected
            // DEC-TED [11,3,6]: P = [31, 103, 171]
            // 31  = 8'b00011111 (d0 covers p0, p1, p2, p3, p4)
            // 103 = 8'b01100111 (d1 covers p0, p1, p2, p5, p6)
            // 171 = 8'b10101011 (d2 covers p0, p1, p3, p5, p7)
            wire p0 = data[0] ^ data[1] ^ data[2];
            wire p1 = data[0] ^ data[1] ^ data[2];
            wire p2 = data[0] ^ data[1];
            wire p3 = data[0] ^ data[2];
            wire p4 = data[0];
            wire p5 = data[1] ^ data[2];
            wire p6 = data[1];
            wire p7 = data[2];
            assign code = {data, p7, p6, p5, p4, p3, p2, p1, p0};
        end
    endgenerate

endmodule
"""
    with open(enc_path, "w") as f:
        f.write(enc_content)
    print(f"[*] Generated: {enc_path}")

    # 3. state_ecc_dec.v
    t1_map = build_syndromes_map(3, 4, 7, 1, [7, 13, 11])
    t2_map = build_syndromes_map(3, 8, 11, 2, [31, 103, 171])

    t1_cases = []
    for s in sorted(t1_map.keys(), key=lambda x: (t1_map[x][0], x)):
        wt, pat = t1_map[s]
        t1_cases.append(f"                    4'd{s}: begin err_pat = 7'b{pat:07b}; err_wt = 2'd{wt}; uncorr = 1'b0; end")
    t1_cases_str = "\n".join(t1_cases)

    t2_cases = []
    for s in sorted(t2_map.keys(), key=lambda x: (t2_map[x][0], x)):
        wt, pat = t2_map[s]
        t2_cases.append(f"                    8'd{s}: begin err_pat = 11'b{pat:011b}; err_wt = 2'd{wt}; uncorr = 1'b0; end")
    t2_cases_str = "\n".join(t2_cases)

    dec_path = os.path.join(out_dir, "state_ecc_dec.v")
    dec_content = f"""`timescale 1ns / 1ps
// =============================================================================
// File:        state_ecc_dec.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Parameterized Combinational FSM State Register ECC Decoder.
//              Supports both:
//                - T_ERR = 2 (default): DEC-TED [11, 3, 6], 67 table entries, corrects 2 bits.
//                - T_ERR = 1          : SECDED  [7, 3, 4],  8 table entries, corrects 1 bit.
//
// Behavior:
//   - Flips <= T_ERR are repaired locally and raise corrected_err (single_err / double_err).
//   - Flips > T_ERR raise uncorrectable (copy_bad) when detectable.
//   - For T_ERR = 2, d_min = 6 mathematically guarantees 100% detection of all 165
//     weight-3 bit flips as uncorrectable with 0 miscorrections.
// =============================================================================

module state_ecc_dec #(
    parameter DATA_W = 3,
    parameter T_ERR  = 2,
    parameter CHK_W  = (T_ERR == 1) ? 4 : 8,
    parameter CW_W   = DATA_W + CHK_W
)(
    input  wire [CW_W-1:0]   code,
    output wire [DATA_W-1:0] data_corrected,
    output wire [CW_W-1:0]   code_corrected,
    output wire [1:0]        error_weight,
    output wire              uncorrectable,
    output wire              single_err,
    output wire              double_err,
    output wire              corrected_err,
    output wire [CHK_W-1:0]  syndrome
);

    generate
        if (CHK_W == 4 || T_ERR == 1) begin : gen_t1_secded
            // Syndrome Calculation for [7,3,4] SECDED
            wire [3:0] syn;
            assign syn[0] = code[4] ^ code[5] ^ code[6] ^ code[0];
            assign syn[1] = code[4] ^ code[6] ^ code[1];
            assign syn[2] = code[4] ^ code[5] ^ code[2];
            assign syn[3] = code[5] ^ code[6] ^ code[3];

            reg [6:0] err_pat;
            reg [1:0] err_wt;
            reg       uncorr;

            always @(*) begin
                case (syn)
{t1_cases_str}
                    default: begin
                        err_pat = 7'b0000000;
                        err_wt  = 2'd0;
                        uncorr  = 1'b1;
                    end
                endcase
            end

            wire [6:0] corr_code = code[6:0] ^ err_pat;

            assign syndrome       = syn;
            assign code_corrected = corr_code;
            assign data_corrected = corr_code[6:4];
            assign error_weight   = err_wt;
            assign uncorrectable  = uncorr;
            assign single_err     = (err_wt == 2'd1);
            assign double_err     = 1'b0;
            assign corrected_err  = (err_wt != 2'd0);

        end else begin : gen_t2_dected
            // Syndrome Calculation for [11,3,6] DEC-TED
            wire [7:0] syn;
            assign syn[0] = code[8] ^ code[9] ^ code[10] ^ code[0];
            assign syn[1] = code[8] ^ code[9] ^ code[10] ^ code[1];
            assign syn[2] = code[8] ^ code[9] ^ code[2];
            assign syn[3] = code[8] ^ code[10] ^ code[3];
            assign syn[4] = code[8] ^ code[4];
            assign syn[5] = code[9] ^ code[10] ^ code[5];
            assign syn[6] = code[9] ^ code[6];
            assign syn[7] = code[10] ^ code[7];

            reg [10:0] err_pat;
            reg [1:0]  err_wt;
            reg        uncorr;

            always @(*) begin
                case (syn)
{t2_cases_str}
                    default: begin
                        err_pat = 11'b00000000000;
                        err_wt  = 2'd0;
                        uncorr  = 1'b1;
                    end
                endcase
            end

            wire [10:0] corr_code = code[10:0] ^ err_pat;

            assign syndrome       = syn;
            assign code_corrected = corr_code;
            assign data_corrected = corr_code[10:8];
            assign error_weight   = err_wt;
            assign uncorrectable  = uncorr;
            assign single_err     = (err_wt == 2'd1);
            assign double_err     = (err_wt == 2'd2);
            assign corrected_err  = (err_wt != 2'd0);

        end
    endgenerate

endmodule
"""
    with open(dec_path, "w") as f:
        f.write(dec_content)
    print(f"[*] Generated: {dec_path}")
    return len(t1_map), len(t2_map)

def print_summary(k, chk, n, t, d_min, table_entries, target_name=""):
    print("------------------------------------------------------------------")
    print(f"   ECC SUMMARY: {target_name.upper()} (DATA_W={k}, T={t})")
    print("------------------------------------------------------------------")
    print(f"    Information Payload (k)       : {k} bits")
    print(f"    Parity Check Bits (chk)       : {chk} bits")
    print(f"    Codeword Width per Copy (CW)  : {n} bits")
    print(f"    Minimum Hamming Distance      : {d_min}")
    print(f"    Decoder Lookup Table Entries  : {table_entries}")
    code_type = "DEC-TED (Double-Error-Correcting, Triple-Error-Detecting)" if (t >= 2 and d_min >= 2*t + 2) else \
                "SECDED (Single-Error-Correcting, Double-Error-Detecting)" if (t == 1 and d_min >= 4) else \
                "DEC (Double-Error-Correcting)" if d_min >= 2*t + 1 else "Linear Binary Code"
    print(f"    Code Classification           : {code_type}")
    print(f"    Check-Bit Overhead            : {(chk / k) * 100:.2f}% (parity/data), {(chk / n) * 100:.2f}% (parity/total)")
    print("------------------------------------------------------------------")

def main():
    args = parse_args()
    out_dir = args.out_dir
    
    if not os.path.isabs(out_dir):
        if os.path.exists(os.path.join("rhbd_mem_ctrl", out_dir)):
            out_dir = os.path.abspath(os.path.join("rhbd_mem_ctrl", out_dir))
        elif os.path.exists(out_dir) or os.path.exists(os.path.dirname(out_dir) or "."):
            out_dir = os.path.abspath(out_dir)
        else:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            proj_dir = os.path.dirname(script_dir)
            out_dir = os.path.join(proj_dir, out_dir)
        
    os.makedirs(out_dir, exist_ok=True)
    
    print("==================================================================")
    print("   AUTOMATED ECC CODE GENERATOR (RHBD MEMORY CONTROLLER)          ")
    print("==================================================================")
    
    if args.target == "all":
        # 1. Memory ECC: DATA_W=8, T=2 DEC-TED (CW=18, CHK=10, d_min=6)
        chk_mem, P_mem, d_mem, _ = find_ecc_matrix(8, 2)
        generate_header(out_dir, 8, chk_mem, 18, 2, d_mem, prefix="")
        generate_encoder(out_dir, 8, chk_mem, 18, P_mem, prefix="", t=2)
        tbl_mem = generate_decoder(out_dir, 8, chk_mem, 18, 2, P_mem, prefix="")
        print_summary(8, chk_mem, 18, 2, d_mem, tbl_mem, "Memory ECC (DEC-TED)")
        
        # 2. Unified FSM State ECC (DATA_W=3, T_STATE=2 default and T_STATE=1 supported)
        t1_tbl, t2_tbl = generate_unified_state_ecc(out_dir)
        if args.t_state == 2:
            print_summary(3, 8, 11, 2, 6, t2_tbl, "State Register ECC (T_STATE=2 DEC-TED, Default)")
            print(f"[Note] State ECC also supports T_STATE=1 SECDED (CW=7, d_min=4, table={t1_tbl}) via parameter T_STATE.")
        else:
            print_summary(3, 4, 7, 1, 4, t1_tbl, "State Register ECC (T_STATE=1 SECDED)")
            print(f"[Note] State ECC also supports T_STATE=2 DEC-TED (CW=11, d_min=6, table={t2_tbl}) via parameter T_STATE.")
            
    elif args.target == "state" or (args.data_w == 3):
        t_req = args.t if ("--t" in sys.argv or unknown) else args.t_state
        t1_tbl, t2_tbl = generate_unified_state_ecc(out_dir)
        if t_req == 2:
            print_summary(3, 8, 11, 2, 6, t2_tbl, "State Register ECC (T_STATE=2 DEC-TED)")
        else:
            print_summary(3, 4, 7, 1, 4, t1_tbl, "State Register ECC (T_STATE=1 SECDED)")
            
    elif args.target == "mem" or (args.data_w == 8 and args.t == 2):
        chk_mem, P_mem, d_mem, _ = find_ecc_matrix(8, 2)
        generate_header(out_dir, 8, chk_mem, 18, 2, d_mem, prefix="")
        generate_encoder(out_dir, 8, chk_mem, 18, P_mem, prefix="", t=2)
        tbl_mem = generate_decoder(out_dir, 8, chk_mem, 18, 2, P_mem, prefix="")
        print_summary(8, chk_mem, 18, 2, d_mem, tbl_mem, "Memory ECC (DEC-TED)")
        
    else:
        # Custom ECC Generation
        k = args.data_w
        t = args.t
        prefix = args.prefix
        chk, P, d_min, _ = find_ecc_matrix(k, t)
        n = k + chk
        generate_header(out_dir, k, chk, n, t, d_min, prefix)
        generate_encoder(out_dir, k, chk, n, P, prefix, t=t)
        tbl = generate_decoder(out_dir, k, chk, n, t, P, prefix)
        print_summary(k, chk, n, t, d_min, tbl, f"Custom ECC ({prefix})")
        
    print("==================================================================")
    print("   ECC GENERATION COMPLETE & VERIFIED. READY FOR RTL COMPILATION! ")
    print("==================================================================")

if __name__ == "__main__":
    main()
