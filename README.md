# Radiation-Hardened-by-Design (RHBD) Memory Controller with Secure Zeroization

A complete, simulation-ready, synthesis-grade RTL Verilog-2001 project designed for aerospace, satellite, and high-security defense applications. Targeted for the **Xilinx Artix-7 FPGA (AMD Vivado 2026.2)** and fully compatible with open-source tools including **Icarus Verilog** and **GTKWave**.

---

## 1. Project Architecture Overview

Digital electronics deployed in harsh radiation environments (such as low Earth orbit, deep space, high-altitude avionics, and nuclear instrumentation) are subject to ionizing radiation and high-energy particle strikes. These strikes cause **Single Event Effects (SEE)**, predominantly:
- **Single Event Upsets (SEUs)**: Transient radiation strikes that flip a bit in a memory storage cell or control register.
- **Multiple Event Upsets (MEUs)**: High-energy heavy-ion strikes or clustered particle impacts that flip multiple bits in adjacent cells.

Additionally, secure crypto-processors, key-storage units, and defense electronics must implement **Anti-Tamper Physical Security** to prevent reverse-engineering or side-channel data extraction when a security breach or tamper sensor trip is detected.

This project implements a multi-tier **Radiation-Hardened-by-Design (RHBD)** memory subsystem featuring:
1. **SECDED Hamming Code Protection**: Protects 8-bit memory words with 5 parity bits (13-bit codeword), enabling automatic Single-Error Correction and Double-Error Detection.
2. **On-Demand & Preemptive Self-Healing**: Hardware in-situ write-back automatically repairs corrupted codewords in physical SRAM during host reads.
3. **Autonomous Background Memory Scrubber**: Continuously scans idle memory addresses to discover and repair latent single-bit errors before a second radiation strike creates an uncorrectable multi-bit fault.
4. **Triple Modular Redundancy (TMR) FSM Protection**: Protects controller sequencing with triplicated state registers and a majority voter, achieving single-cycle autonomous self-healing upon state upset.
5. **Multi-Pass DoD 5220.22-M Style Zeroization**: Instantly overwrites the entire memory array with alternating bit patterns (0x00 -> 0xFF -> 0x00) and performs an autonomous post-wipe verification sweep upon tamper detection.

---

## 2. ASCII Block Diagram

```text
                                 +-----------------------------------------------------------+
                                 |                      rhbd_mem_top                         |
                                 |                                                           |
  [Host Interface]               |  +--------------------+             +------------------+  |
  req_wr, req_rd --------------->|  |   mem_ctrl_fsm     |   Grant     |     scrubber     |  |
  host_addr [7:0] -------------->|  |  (TMR Protected)   |<----------->| (Auto Background)|  |
  host_wdata [7:0] ------------->|  |   [Copy 0, 1, 2]   |             +------------------+  |
  host_rdata [7:0] <-------------|  |         |          |                      |            |
  rdata_valid <------------------|  |    tmr_voter       |                      |            |
  busy <-------------------------|  +---------+----------+                      |            |
                                 |            |                                 |            |
  [Security / Tamper]            |            v                                 |            |
  tamper ----------------------->|  +--------------------+                      |            |
                                 |  |  zeroize_engine    |                      |            |
  [Fault Injection]              |  | (DoD Multi-Pass)   |                      |            |
  inject_en, inject_mask ------->|  +---------+----------+                      |            |
  fsm_fault_inject [2:0] ------->|            |                                 |            |
                                 |            v                                 v            |
                                 |     +-----------------------------------------------+     |
                                 |     |             RAM Bus Arbiter / Mux             |     |
                                 |     +-----------------------+-----------------------+     |
                                 |                             |                             |
                                 |       we, addr [7:0], din [12:0], dout [12:0]             |
                                 |                             v                             |
                                 |             +-------------------------------+             |
                                 |             |            ecc_ram            |             |
                                 |             |      (13-bit x 256 Words)     |             |
                                 |             +-------------------------------+             |
                                 |                             |                             |
                                 |                             v                             |
                                 |             +-------------------------------+             |
                                 |             |       hamming_secded_dec      |             |
                                 |             +---------------+---------------+             |
                                 |                             |                             |
                                 |     +-----------------------+-----------------------+     |
                                 |     |                       |                       |     |
                                 |     v                       v                       v     |
  [Status Telemetry]             | single_err_seen       double_err_seen          tmr_mismatch
  corrected_count [15:0] <-------| zeroize_busy          zeroize_done             zeroize_fail
  uncorrectable_count [15:0] <---|                                                           |
                                 +-----------------------------------------------------------+
```

---

## 3. Module Hierarchy & Function Breakdown

| Module | File Path | Description & RHBD Functionality |
| :--- | :--- | :--- |
| **`hamming_secded_enc`** | `rtl/hamming_secded_enc.v` | Computes Hamming(12,8) parities ($p_1, p_2, p_4, p_8$) plus overall even parity ($p_0$). Guarantees `8'h00` encodes to `13'h0000`. |
| **`hamming_secded_dec`** | `rtl/hamming_secded_dec.v` | Pure combinational SECDED decoder; extracts 4-bit syndrome, classifies Single vs. Double errors, outputs corrected data and codeword. |
| **`tmr_voter`** | `rtl/tmr_voter.v` | Parameterized Triple Modular Redundancy majority voter (`y = (a&b) \| (b&c) \| (a&c)`) with mismatch detection flag. |
| **`ecc_ram`** | `rtl/ecc_ram.v` | 13-bit wide, 256-word synchronous SRAM with hardware fault injection port (`inject_en`, `inject_mask`). |
| **`scrubber`** | `rtl/scrubber.v` | Autonomous background engine patrolling memory addresses during IDLE cycles to prevent latent SEU accumulation. |
| **`zeroize_engine`** | `rtl/zeroize_engine.v` | Multi-pass military anti-tamper memory wipe engine with automatic post-wipe verification pass. |
| **`mem_ctrl_fsm`** | `rtl/mem_ctrl_fsm.v` | Triplicated state register FSM using 3-bit Gray code; self-heals corrupted state copies on every clock edge. |
| **`rhbd_mem_top`** | `rtl/rhbd_mem_top.v` | Top-level system integration tying together host arbitration, SECDED datapath, TMR FSM, scrubber, and zeroizer. |
| **`fpga_top`** | `rtl/fpga_top.v` | Physical FPGA synthesis wrapper with button debouncers, pulse stretchers, status LEDs, and 4-digit seven-segment display. |

---

## 4. Codeword Layout & SECDED Mathematical Theory

The SECDED scheme encodes an 8-bit data payload $d[7:0]$ into a 13-bit codeword $c[12:0]$.
Positions 1 through 12 follow standard 1-indexed Hamming bit positions, with overall parity placed at bit 0:

| Codeword Bit | Identifier | Function / Hamming Group Coverage |
| :---: | :---: | :--- |
| **`c[0]`** | $p_0$ | Overall even parity across bits $c[12:1]$ |
| **`c[1]`** | $p_1$ | Parity for positions with LSB=1: $\{1, 3, 5, 7, 9, 11\} \rightarrow \{p_1, d_0, d_1, d_3, d_4, d_6\}$ |
| **`c[2]`** | $p_2$ | Parity for positions with bit 1=1: $\{2, 3, 6, 7, 10, 11\} \rightarrow \{p_2, d_0, d_2, d_3, d_5, d_6\}$ |
| **`c[3]`** | $d_0$ | Data payload bit 0 |
| **`c[4]`** | $p_4$ | Parity for positions with bit 2=1: $\{4, 5, 6, 7, 12\} \rightarrow \{p_4, d_1, d_2, d_3, d_7\}$ |
| **`c[5]`** | $d_1$ | Data payload bit 1 |
| **`c[6]`** | $d_2$ | Data payload bit 2 |
| **`c[7]`** | $d_3$ | Data payload bit 3 |
| **`c[8]`** | $p_8$ | Parity for positions with bit 3=1: $\{8, 9, 10, 11, 12\} \rightarrow \{p_8, d_4, d_5, d_6, d_7\}$ |
| **`c[9]`** | $d_4$ | Data payload bit 4 |
| **`c[10]`** | $d_5$ | Data payload bit 5 |
| **`c[11]`** | $d_6$ | Data payload bit 6 |
| **`c[12]`** | $d_7$ | Data payload bit 7 |

### Error Classification Table
Let $S = syn[3:0]$ be the 4-bit syndrome and $P = \bigoplus_{i=0}^{12} c[i]$ be the total parity reduction:

| Total Parity ($P$) | Syndrome ($S$) | Error Category | Action Taken |
| :---: | :---: | :--- | :--- |
| $0$ (Even) | $0000_2$ | **No Error** | Codeword is valid; proceed normally. |
| $1$ (Odd) | $0001_2 \dots 1100_2$ | **Single Bit Error** (Bits 1..12) | Correct bit $c[S]$ by inverting it; write back to RAM. |
| $1$ (Odd) | $0000_2$ | **Single Bit Error** (Bit 0 / $p_0$) | Data payload is unaffected; repair parity bit. |
| $0$ (Even) | $\neq 0000_2$ | **Double Bit Error** (Uncorrectable) | Assert `double_err_seen`; halt host access / trap. |
| $1$ (Odd) | $> 12$ ($13, 14, 15$) | **Multi-Bit Error** | Flagged as uncorrectable anomaly. |

---

## 5. Verification & Test Suite

The testbench suite is 100% self-checking, logs all assertions, dumps `.vcd` waveform files, and terminates with `$finish`.

| Testbench | Focus Area | Checks Performed |
| :--- | :--- | :--- |
| **`tb_ecc.v`** | Pure SECDED Math | Exhaustive check of all 256 data words; bit-by-bit single error injection across 13 bits; pairwise double-bit error injection across all pairs (413 total checks). |
| **`tb_ram_faults.v`** | Memory & Write-Back | Write payload, inject single-bit SEU via RAM port, confirm read repair, re-read to verify in-situ write-back; inject double-bit SEU and verify uncorrectable trap. |
| **`tb_fsm_tmr.v`** | TMR FSM Self-Healing | Inject faults into Copy 0, 1, and 2 in IDLE and during live WRITE and READ cycles; confirm `state_mismatch` assertion, single-cycle self-healing, and `tmr_fix_count` incrementing. |
| **`tb_zeroize.v`** | Anti-Tamper Zeroization | Pre-fill all 256 memory words with random data; trigger tamper; verify host bus lock; confirm 3-pass DoD overwrite; verify 256-word sweep reads 0x00. |
| **`tb_top.v`** | Full System Integration | 7-phase end-to-end mission scenario combining boot, host read/write, SEU correction, autonomous background scrubbing, TMR FSM upset, and emergency zeroization. |

---

## 6. How to Run Simulations

### Option A: Using Icarus Verilog on Linux or macOS
```bash
cd rhbd_mem_ctrl/sim
chmod +x run_iverilog.sh
./run_iverilog.sh
```

### Option B: Using Windows Command Prompt / PowerShell
Run the pre-configured batch script:
```powershell
cd rhbd_mem_ctrl\sim
.\run_sim.bat
```
Or execute individual testbenches directly:
```powershell
iverilog -g2001 -o tb_top.vvp ../tb/tb_top.v ../rtl/*.v
vvp tb_top.vvp
gtkwave tb_top.vcd
```

### Option C: Using AMD Xilinx Vivado 2026.2 (xsim)
In Vivado Tcl Console or PowerShell with Vivado bin in PATH:
```powershell
cd rhbd_mem_ctrl
xvlog rtl/*.v tb/*.v
xelab -top tb_top -snapshot tb_top_snap
xsim tb_top_snap -R
```

---

## 7. How to Add Files into Vivado & Build Bitstream

1. **Open Vivado 2026.2**:
   Launch Vivado and click **Create Project** or open the existing project `rhbd_mem_ctrl.xpr`.
2. **Select Target Device**:
   Select your Artix-7 board (e.g., Basys 3 `xc7a35tcpg236-1` or Nexys A7-100T `xc7a100tcsg324-1`).
3. **Add Design Sources**:
   - Click **Add Sources** -> **Add or create design sources**.
   - Browse to `rhbd_mem_ctrl/rtl/` and select all `.v` files:
     - `hamming_secded_enc.v`
     - `hamming_secded_dec.v`
     - `tmr_voter.v`
     - `ecc_ram.v`
     - `scrubber.v`
     - `zeroize_engine.v`
     - `mem_ctrl_fsm.v`
     - `rhbd_mem_top.v`
     - `fpga_top.v` (Set as Top Module for Implementation)
4. **Add Constraints**:
   - Click **Add Sources** -> **Add or create constraints**.
   - Add `rhbd_mem_ctrl/constraints/board.xdc`.
   - **Edit pin numbers in `board.xdc`** to match your board schematic.
5. **Run Synthesis & Implementation**:
   - Click **Run Synthesis**.
   - Click **Run Implementation**.
   - Click **Generate Bitstream**.
6. **Program Board**:
   Open Hardware Manager, auto-connect to your board via USB-JTAG, and program the device.

---

## 8. College Viva Voce Preparation (10 Q&A)

### Q1: What is the difference between SECDED and basic Hamming code?
**Answer:** A standard Hamming code with distance $d_{min}=3$ can only correct single-bit errors or detect double-bit errors, but it cannot differentiate between them (a double-bit error produces a false syndrome that leads to incorrect bit flipping). SECDED adds an overall even-parity bit $p_0$, expanding minimum Hamming distance to $d_{min}=4$. This allows the decoder to mathematically distinguish between an odd number of errors (single-bit, which flips total parity) and an even number of errors (double-bit, which maintains total parity but produces a non-zero syndrome).

### Q2: Why is data `8'h00` required to encode into `13'h0000`?
**Answer:** When memory is initialized or securely zeroized, physical memory cells are forced to all-zero states ($13'h0000$). If `8'h00` did not encode to all-zeros (for example, in odd-parity schemes where parity bits would be 1), reading unwritten or zeroized memory would falsely trigger parity error alarms. Even parity ensures that 0 data produces 0 parity, creating complete mathematical harmony with hardware zeroization.

### Q3: What is Triple Modular Redundancy (TMR) and how does it self-heal?
**Answer:** TMR duplicates a critical functional unit or register three times (`state_r0`, `state_r1`, `state_r2`) and routes them through a majority voter. If an ionizing particle strikes one flip-flop and flips its state, the remaining two copies maintain the correct state. By feeding the voted state into the next-state logic and rewriting all three registers every clock cycle, the corrupted register is overwritten and healed on the very next clock edge without interrupting system operation.

### Q4: Why is Gray code used for the FSM states instead of Binary or One-Hot?
**Answer:** In Gray coding, successive states differ by only a single bit flip. This minimizes the Hamming distance between transitions, reducing dynamic switching noise and minimizing the vulnerability window for glitch-induced SEUs. Furthermore, 3-bit Gray code is compact, making TMR voting logic lightweight compared to triplicating 7-bit one-hot registers.

### Q5: What is the purpose of an autonomous background memory scrubber?
**Answer:** Single-bit errors in memory are harmless if corrected promptly. However, if a memory address is rarely accessed by the host, a single latent radiation upset can sit undetected. If a second radiation particle strikes the same word before it is read, the error becomes an uncorrectable double-bit error. The scrubber autonomously scans all memory words in the background during IDLE cycles, identifying single-bit errors and writing back repaired codewords before error accumulation can occur.

### Q6: How does the scrubber prevent starving the host processor?
**Answer:** The scrubber possesses lowest bus priority. When the controller is idle for `SCRUB_INTERVAL` cycles, the scrubber requests a single address check. If a host read or write request (`req_wr`, `req_rd`) or tamper event arrives at any time, the scrubber immediately deasserts its request, yields memory ownership to the host, and preserves its current address pointer so it resumes seamlessly when the host finishes.

### Q7: What standards govern secure memory zeroization?
**Answer:** Secure zeroization follows military and government specifications such as **DoD 5220.22-M** and **NIST SP 800-88**. Simple one-pass zeroing can leave analog electrical hysteresis in physical storage cells. Multi-pass overwrite (Pass 1: zeros, Pass 2: ones, Pass 3: zeros) followed by a hardware verification pass ensures complete physical sanitization of crypto keys and sensitive data.

### Q8: What happens when an uncorrectable double error is detected during a host read?
**Answer:** When `double_err_seen` asserts, the controller refuses to supply corrupted data to the host. In high-reliability fail-safe architectures, the controller transitions to `ST_LOCKED_ERR`, locks the host bus (`busy = 1`), and alerts supervisory system software. The lock can only be cleared by a deliberate system reset or an emergency anti-tamper zeroization.

### Q9: Can the TMR voter itself suffer an SEU?
**Answer:** The voter is purely combinational logic consisting of AND-OR gates. While combinational logic does not permanently store charge (unlike flip-flops), high-energy particles can induce transient voltage glitches (Single Event Transients - SETs). In ultra-high reliability ASICs and space-grade FPGAs, voter logic can be triplicated or hardened with RC filtering, or distributed at the input of every receiver flip-flop.

### Q10: How does the FPGA demonstration wrapper allow a viva examiner to test fault tolerance?
**Answer:** The `fpga_top` module routes push buttons and slide switches to dedicated hardware fault injectors:
- Pressing `btn_inj_1bit` flips 1 bit in physical SRAM at `sw_addr`; reading that address lights up `led_single_err` and displays the restored data on seven-segment LEDs.
- Pressing `btn_inj_2bit` flips 2 bits; reading that address triggers `led_double_err`.
- Pressing `btn_inj_fsm` flips a state register copy; `led_tmr_mismatch` pulses while the FSM continues running smoothly.
- Pressing `btn_tamper` executes a 3-pass wipe, lighting `led_zeroize_busy` then `led_zeroize_done`.

