###########################################################
## asap7_setup.tcl
##
## ASAP7 RVT common setup
## Sourced by both synth.tcl (Genus) and pnr.tcl (Innovus)
###########################################################

set ASAP7_ROOT  "$::env(HOME)/pdk/asap7"
set ASAP7_LIB   "$ASAP7_ROOT/asap7sc7p5t_28/LIB/NLDM"
set ASAP7_SRAM  "$ASAP7_ROOT/asap7_sram_0p0/generated/LIB"
set ASAP7_LEF   "$ASAP7_ROOT/asap7sc7p5t_28/LEF/scaled"
set ASAP7_TECH  "$ASAP7_ROOT/asap7sc7p5t_28/techlef_misc"
set ASAP7_GDS   "$ASAP7_ROOT/asap7sc7p5t_28/GDS"
set ASAP7_QRC   "$ASAP7_ROOT/asap7sc7p5t_28/qrc"
set ASAP7_VLOG  "$ASAP7_ROOT/asap7sc7p5t_28/Verilog"
set ASAP7_SITE  "asap7sc7p5t"

# Single-corner library set for Genus (TT, RVT, all five cell families)
set ASAP7_LIB_TT [list \
    "$ASAP7_LIB/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"    \
    "$ASAP7_LIB/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib" \
    "$ASAP7_LIB/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib"     \
    "$ASAP7_LIB/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib"     \
    "$ASAP7_LIB/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib" \
]

# Multi-corner library sets (SS for setup signoff, FF for hold signoff)
set ASAP7_LIB_SS [list \
    "$ASAP7_LIB/asap7sc7p5t_SEQ_RVT_SS_nldm_220123.lib"    \
    "$ASAP7_LIB/asap7sc7p5t_SIMPLE_RVT_SS_nldm_211120.lib" \
    "$ASAP7_LIB/asap7sc7p5t_AO_RVT_SS_nldm_211120.lib"     \
    "$ASAP7_LIB/asap7sc7p5t_OA_RVT_SS_nldm_211120.lib"     \
    "$ASAP7_LIB/asap7sc7p5t_INVBUF_RVT_SS_nldm_220122.lib" \
]

set ASAP7_LIB_FF [list \
    "$ASAP7_LIB/asap7sc7p5t_SEQ_RVT_FF_nldm_220123.lib"    \
    "$ASAP7_LIB/asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib" \
    "$ASAP7_LIB/asap7sc7p5t_AO_RVT_FF_nldm_211120.lib"     \
    "$ASAP7_LIB/asap7sc7p5t_OA_RVT_FF_nldm_211120.lib"     \
    "$ASAP7_LIB/asap7sc7p5t_INVBUF_RVT_FF_nldm_220122.lib" \
]

#              Technology LEF for Innovus (4x-scaled flow):
# The stock asap7_tech_4x_201209.lef writes its single-cut V3/V5 cut
# enclosure rules in the EOL form with an eolWidth of 0.0, e.g.
#     ENCLOSURE CUTCLASS V3 BELOW EOL 0.0 0.020 0.0 ;
# No wire edge can ever qualify as an end-of-line at width 0, so Innovus
# 25.10 warns (NRDB-2012) and then reports a VIAENCLOSURE violation on
# essentially every single-cut V3/V5 via. This occurs even though the 
# LEF's own default vias (e.g. VIA34) provide exactly the overhangs the 
# author intended, as their own commented-out line shows:
#     # ENCLOSURE CUTCLASS V3 END 0.02 SIDE 0.0 
# The bash file `patch_asap7_lef.sh` rewrites just those lines into 
# the END/SIDE form.
set ASAP7_TECH_LEF_STOCK   "$ASAP7_TECH/asap7_tech_4x_201209.lef"
set ASAP7_TECH_LEF_PATCHED "lef/asap7_tech_4x_201209_patched.lef"

if {[file exists $ASAP7_TECH_LEF_PATCHED]} {
    set ASAP7_TECH_LEF $ASAP7_TECH_LEF_PATCHED
    puts "INFO: using PATCHED tech LEF: $ASAP7_TECH_LEF"
} else {
    set ASAP7_TECH_LEF $ASAP7_TECH_LEF_STOCK
    puts "INFO: using stock tech LEF (run scripts/patch_asap7_lef.sh to fix"
    puts "      the V3/V5 cut-enclosure rules and clear the VIAENCLOSURE DRCs)"
}

set ASAP7_LEF_FILES [list \
    "$ASAP7_TECH_LEF" \
    "$ASAP7_LEF/asap7sc7p5t_28_R_4x_220121a.lef" \
]

# Verilog for post-layout simulation
set ASAP7_VLOG_FILES [list \
    "$ASAP7_VLOG/asap7sc7p5t_SEQ_RVT_TT_220101.v"     \
    "$ASAP7_VLOG/asap7sc7p5t_SIMPLE_RVT_TT_201020.v"  \
    "$ASAP7_VLOG/asap7sc7p5t_AO_RVT_TT_201020.v"      \
    "$ASAP7_VLOG/asap7sc7p5t_OA_RVT_TT_201020.v"      \
    "$ASAP7_VLOG/asap7sc7p5t_INVBUF_RVT_TT_201020.v"  \
]

set ASAP7_SRAM_LIB [list \
    "$ASAP7_SRAM/srambank_64x4x32_6t122.lib" \
]

puts "INFO: ASAP7 setup loaded from $ASAP7_ROOT"
