# References

`clockFiles/` holds the TICS Pro register exports supplied with the ZCU111
(LMK04208 U90, LMX2594 U102/U103/U104, Si5382A). The two used by the design
are also copied to `sw/server/clk_tables/`.

The AMD PDFs used during the design are not tracked in git (vendor documents).
Download them from amd.com to this folder:

- `ug1271-zcu111-eval-bd.pdf` – ZCU111 Evaluation Board User Guide (UG1271)
- `0381811_ZCU111_REV1_0_07122018.pdf` – ZCU111 Rev 1.0 schematic (0381811)

`PFB/dfb4096x1c_v2_0/` is the CSIRO fine filter bank (4096-channel DFB with
power accumulation), exported from System Generator 2018.2 as a Vivado IP
repository. `hw/scripts/spec_ip.tcl` adds it to the IP catalog and creates the
instance `dfb4096x1c_0`; Vivado upgrades its sub-cores (Block Memory, FFT,
counters) on generation. The exported `.zip` duplicates the folder and is not
tracked. The spectrometer v1.x coarse cores (`pfb32x16t_v1_6`, `rnd_23_18_v1_0`)
are no longer used and are not in git.
