##################################################################################################
## pnr.tcl
##
## Author: Giovanni Sirtori <gs86@rice.edu> (based on ASU's
## asap7/asap7sc7p5t_28/techlef_misc/example_innovus.tcl)
##
## Description: Runs place and route on Cadence Innovus, 
## targeting ASAP7 RVT.
##
## A component of the mon-CHERI-DMA project.
## https://github.com/adidokkk/mon-CHERI-DMA
##
## Copyright (C) 2025-26 Rice University
##
## SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
##
## Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file
## except in compliance with the License, or, at your option, the Apache License version 2.0. You
## may obtain a copy of the License at
##
## https://solderpad.org/licenses/SHL-2.1/
##
## Unless required by applicable law or agreed to in writing, any work distributed under the
## License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
## either express or implied. See the License for the specific language governing permissions
## and limitations under the License.
##################################################################################################

#   Usage:
#       FREQ=1.2 CHERI_EN=1 innovus -stylus -no_gui -overwrite \
#           -log <path> -files pnr.tcl
#   Default outputs (matches the freq_<f>/syn/ tree):
#       freq_<f>/pnr/reports/*.rpt
#       freq_<f>/pnr/outs/*_{final.vh, .def, .sdf}
#
#   NOTE: ASAP7 has time_unit = 1 ps, capacitive_load_unit = 1 ff
#   NOTE: ASAP7 uses 4x-scaled LEF flow

set_db source_verbose false



### 1.  INPUTS
set DESIGN mCD

# Defaults
set freq       1.2
set cheri_en   0
set pnr_corner typ
set pnr_cpus   8

# Accepts both env vars (recommended) and CLI args
if {[info exists ::env(FREQ)]}       { set freq       $::env(FREQ) }
if {[info exists ::env(CHERI_EN)]}   { set cheri_en   $::env(CHERI_EN) }
if {[info exists ::env(PNR_CORNER)]} { set pnr_corner $::env(PNR_CORNER) }
if {[info exists ::env(PNR_CPUS)]}   { set pnr_cpus   $::env(PNR_CPUS) }

if {[info exists argv]} {
    foreach arg $argv {
        if {[regexp {^([^=]+)=(.*)$} $arg -> key value]} {
            switch -exact -- $key {
                freq       { set freq       $value }
                cheri_en   { set cheri_en   $value }
                pnr_corner { set pnr_corner $value }
                pnr_cpus   { set pnr_cpus   $value }
                default    { puts "WARN: ignoring unknown arg '$arg'" }
            }
        }
    }
}

# Sanity check
if {$cheri_en != 0 && $cheri_en != 1} {
    puts "ERROR: cheri_en must be 0 or 1 (got '$cheri_en')"; exit 1
}
if {![string is double -strict $freq] || $freq <= 0} {
    puts "ERROR: freq must be a positive number in GHz (got '$freq')"; exit 1
}
switch -exact -- $pnr_corner {
    typ     { set SETUP_VIEW av_typ   }
    slow    { set SETUP_VIEW av_setup }
    default { puts "ERROR: PNR_CORNER must be typ or slow (got '$pnr_corner')"; exit 1 }
}
set HOLD_VIEW av_hold

if {$cheri_en} { set TAG CHERI } else { set TAG BASE }
set TOP_MODULE    "${DESIGN}_CHERI_EN${cheri_en}"
set clk_period_ps [expr {1000.0 / $freq}]



### 2. PATHS
set SYN_DIR  "freq_${freq}/syn"
set PNR_DIR  "freq_${freq}/pnr"
set RPT_DIR  "${PNR_DIR}/reports"
set OUT_DIR  "${PNR_DIR}/outs"
set CKPT_DIR "${PNR_DIR}/checkpoints/${TAG}"
set RPT_PFX  "${RPT_DIR}/${DESIGN}_${TAG}"
set OUT_PFX  "${OUT_DIR}/${DESIGN}_${TAG}"

set NETLIST_FILE "${SYN_DIR}/outs/${DESIGN}_${TAG}_netlist.vh"
set SYN_SDC_FILE "${SYN_DIR}/outs/${DESIGN}_${TAG}_constraints.sdc"
set SYN_AREA_RPT "${SYN_DIR}/reports/${DESIGN}_${TAG}_area.rpt"
set MMMC_FILE    "scripts/mCD.view"

file mkdir $RPT_DIR $OUT_DIR $CKPT_DIR

# Summarize a check_drc report by violation type and layer
proc summarize_drc {rpt out} {
    if {![file exists $rpt]} { puts "WARN: summarize_drc: $rpt not found"; return }
    set fh [open $rpt r]; set lines [split [read $fh] "\n"]; close $fh
    array set cnt {}
    set total 0
    foreach l $lines {
        if {[regexp {^\s*([A-Za-z][A-Za-z0-9_]*):\s*\(\s*([^)]*?)\s*\).*\(\s*([A-Za-z0-9_]+)\s*\)\s*$} $l -> type sub layer]} {
            set key [format "%-14s %-24s %s" $type $sub $layer]
            if {[info exists cnt($key)]} { incr cnt($key) } else { set cnt($key) 1 }
            incr total
        }
    }
    set fo [open $out w]
    puts $fo [format "%7s  %-14s %-24s %s" COUNT TYPE SUBTYPE LAYER]
    foreach k [lsort [array names cnt]] { lappend rows [list $cnt($k) $k] }
    if {[info exists rows]} {
        foreach r [lsort -integer -decreasing -index 0 $rows] {
            puts $fo [format "%7d  %s" [lindex $r 0] [lindex $r 1]]
        }
    }
    puts $fo [format "%7d  TOTAL" $total]
    close $fo
    puts "INFO: DRC summary ($total violations) -> $out"
}



### 3. TARGETS
set CORE_UTIL    0.70
set CORE_ASPECT  1.0
set CORE_MARGIN  12;    # um, core-to-die
set LEF_SCALE    4;     # 4x LEF: placed area = syn area * 16

# Clock tree: fixed targets so tree quality does not drift with frequency
# (the validated ASAP7 references use fixed 5 ps / 30 ps).
set CTS_TARGET_SKEW      30
# Clock max transition
set CTS_TARGET_MAX_TRANS 60

# Clock uncertainty in PnR
# The Genus SDC applies 8% of the period as uncertainty to both setup
# and hold. That is the right number for synthesis, where the clock is
# ideal and uncertainty must stand in for skew + jitter. After CTS it
# should be dropped: both values below are jitter/margin only, as real 
# skew comes from the propagated clock tree.
set SETUP_UNCERT         20
set HOLD_UNCERT          10

# Track the synthesis rule and keep 100 ps as an upper bound.
set PNR_MAX_TRANS [expr {min(100.0, 0.15 * $clk_period_ps)}]

# Area of the synthesized netlist determines core size
set syn_area 0
set fh [open $SYN_AREA_RPT r]
foreach line [split [read $fh] "\n"] {
    if {[regexp {(?i)^\s*total\s+.*?([0-9]+\.?[0-9]*)\s*$} $line -> a]} {
        set syn_area $a
        break
    }
}
close $fh
if {$syn_area <= 0} {
    puts "ERROR: could not parse total area from $SYN_AREA_RPT"; exit 1
}
set placed_area [expr {$syn_area * $LEF_SCALE * $LEF_SCALE}]
set core_area   [expr {$placed_area / $CORE_UTIL}]
set core_w      [expr {sqrt($core_area / $CORE_ASPECT)}]
set core_h      [expr {$core_area / $core_w}]

puts ""
puts "######################################################################"
puts "#  PnR : ${TOP_MODULE}  ${freq} GHz (period ${clk_period_ps} ps)  ${TAG}"
puts "#        corner=${pnr_corner} (setup view ${SETUP_VIEW})  cpus=${pnr_cpus}"
puts "#        syn area ${syn_area} um2 -> core ${core_w} x ${core_h} um"
puts "#        uncert setup/hold ${SETUP_UNCERT}/${HOLD_UNCERT} ps  max_tran ${PNR_MAX_TRANS} ps"
puts "######################################################################"
puts ""



### 4. PNR CONSTRAINTS (Genus SDC + PnR overrides)
set SDC_FILE "${PNR_DIR}/${DESIGN}_${TAG}_pnr.sdc"
set fi [open $SYN_SDC_FILE r]; set sdc_text [read $fi]; close $fi
set fo [open $SDC_FILE w]
puts $fo $sdc_text
puts $fo ""
puts $fo "##### PnR overrides (appended by pnr.tcl) #####"
puts $fo "set_clock_uncertainty -setup $SETUP_UNCERT \[all_clocks\]"
puts $fo "set_clock_uncertainty -hold  $HOLD_UNCERT \[all_clocks\]"
puts $fo "set_max_transition $PNR_MAX_TRANS \[current_design\]"
close $fo
puts "INFO: PnR SDC written: $SDC_FILE"



# 5.  PDK + DESIGN INIT
source scripts/asap7_setup.tcl
set ::env(ASAP7_TECH) "$ASAP7_ROOT/asap7sc7p5t_28/techlef_misc"

set_db init_power_nets      {VDD}
set_db init_ground_nets     {VSS}
set_db init_design_uniquify true

foreach __v {SDC_FILE ASAP7_LIB_SS ASAP7_LIB_TT ASAP7_LIB_FF ASAP7_QRC} {
    set ::$__v [set $__v]
}
unset __v
read_mmmc     $MMMC_FILE
read_physical -lef $ASAP7_LEF_FILES
read_netlist  $NETLIST_FILE -top $DESIGN
init_design

set_multi_cpu_usage -local_cpu $pnr_cpus

# setup at the chosen corner (TT by default), hold at FF
set_analysis_view -setup [list $SETUP_VIEW] -hold [list $HOLD_VIEW]

# 7nm x 4 = 28 (asap7sc7p5t_28)
set_db design_process_node  28
set_db timing_analysis_type ocv

# signals in [M2, M7] (as in the reference flows)
set_db design_bottom_routing_layer M2
set_db design_top_routing_layer    M7

# Via-in-pin for M1 standard-cell pins (ASU reference: "so it does not
# extend the M1 pins in cells")
set_db route_with_via_in_pin 1:1

# Please note that 'extreme' roughly doubles runtime
# for small gains
set_db design_flow_effort          standard; 
set_db opt_setup_target_slack      0.020;   # here target slack is in ns
set_db opt_hold_target_slack       0.0
set_db place_global_timing_driven  true

puts "INFO: init done (top=$TOP_MODULE, setup=$SETUP_VIEW, hold=$HOLD_VIEW)"



### 5. FLOORPLAN + ASAP7 TRACK FIXES + I/O PINS
# IMPTR-2101 ("Layer M10: Pitch=11520x9 is still less than min width=32000
# + min spacing=640") refers to routing layer 10 = Pad. Its LEF minimum
# width is 8 um but its LEF pitch is 0.32 um, so add_tracks -honor_pitch 
# cannot build a legal track at any multiple of the pitch. 
# This seems a PDK-LEF inconsistency (routing is capped at M7), thus it is
# reported as a warning and not error.
set_message -id IMPTR-2101 -severity warn

create_floorplan \
    -site         $ASAP7_SITE \
    -core_size    [list $core_w $core_h $CORE_MARGIN $CORE_MARGIN $CORE_MARGIN $CORE_MARGIN] \
    -core_margins_by die

eval_legacy {
    add_tracks -honor_pitch
    changeFloorplan -coreToBottom 1.08
}

set_db assign_pins_bottom_layer M2
set_db assign_pins_top_layer    M4
assign_io_pins

write_db $CKPT_DIR/01_floorplan.db
puts "INFO: floorplan + pins done"


### 6. POWER PLANNING
# ASAP7 validated recipe (legacy)
# Mesh:  M1 follow-pins -> M2 overlay rails (m2followRail.tcl)
#        -> M3 (V) -> M4 (H) -> M5 (V) -> M6 (H)
eval_legacy {
    # 6.1 : Global-net connections
    clearGlobalNets
    globalNetConnect VDD -type pgpin -pin VDD -inst * -module {}
    globalNetConnect VSS -type pgpin -pin VSS -inst * -module {}

    # 6.2 : Well-tap cells
    addWellTap -cell TAPCELL_ASAP7_75t_R -cellInterval 50 -inRowOffset 10.564

    # 6.3 : Connect M1 follow-pins to the grid
    setAddStripeMode -stacked_via_bottom_layer M1 -stacked_via_top_layer M2
    sroute -connect { blockPin padPin padRing corePin floatingStripe } \
        -layerChangeRange { M1 Pad } \
        -blockPinTarget { nearestTarget } \
        -padPinPortConnect { allPort oneGeom } \
        -padPinTarget { nearestTarget } \
        -corePinTarget { firstAfterRowEnd } \
        -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } \
        -allowJogging 1 \
        -crossoverViaLayerRange { M1 Pad } \
        -nets { VDD VSS } \
        -allowLayerChange 1 \
        -blockPin useLef \
        -targetViaLayerRange { M1 }

    # 6.4 : Fix the top M1 follow-rail with the M2 overlay helper
    source $::env(ASAP7_TECH)/m2followRail.tcl

    # 6.5 : Upper-layer power mesh (M3/M4/M5/M6)
    setViaGenMode -viarule_preference { M6_M5widePWR1p152 M5_M4widePWR0p864 M4_M3widePWR0p864 }

    # 6.5.1 : M3 (vertical)
    set m3pwrwidth        [expr 0.072 * (5 + (4 * 2))]
    set m3pwrset2settracks 220
    set m3pwrset2setdist   [expr $m3pwrset2settracks * 0.144]
    set m3pwrspacing       [expr 0.072 * 21]
    set m3pwrxoffset       [expr (0.072 * 26) + 0.036]
    print "M3 PWR width/set2set/spacing/offset: $m3pwrwidth $m3pwrset2setdist $m3pwrspacing $m3pwrxoffset"
    addStripe -extend_to design_boundary \
        -skip_via_on_wire_shape Noshape \
        -max_same_layer_jog_length 0.32 \
        -set_to_set_distance $m3pwrset2setdist \
        -skip_via_on_pin Standardcell \
        -stacked_via_top_layer Pad \
        -spacing $m3pwrspacing \
        -xleft_offset $m3pwrxoffset \
        -merge_stripes_value 0.16 \
        -layer M3 \
        -width $m3pwrwidth \
        -nets {VDD VSS} \
        -stacked_via_bottom_layer M2

    # 6.5.2 : M4 (horizontal)
    set m4pwrwidth        [expr 0.096 * (5 + (4 * 1))]
    set m4pwrset2settracks 320
    set m4pwrset2setdist   [expr $m4pwrset2settracks * 0.192]
    set m4pwrspacing       [expr 0.096 * 21]
    set m4pwrxoffset       [expr (0.096 * 26) - 0.036]
    print "M4 PWR width/set2set/spacing/offset: $m4pwrwidth $m4pwrset2setdist $m4pwrspacing $m4pwrxoffset"
    setAddStripeMode \
        -max_via_size { Stripe 100 100 100 } \
        -via_using_exact_crossover_size true \
        -stacked_via_bottom_layer M3 \
        -stacked_via_top_layer M4
    addStripe -extend_to design_boundary \
        -direction horizontal \
        -skip_via_on_wire_shape Noshape \
        -max_same_layer_jog_length 0.32 \
        -set_to_set_distance $m4pwrset2setdist \
        -skip_via_on_pin Standardcell \
        -spacing $m4pwrspacing \
        -start_offset $m4pwrxoffset \
        -merge_stripes_value 0.16 \
        -layer M4 \
        -width $m4pwrwidth \
        -nets {VDD VSS}

    # 6.5.3 : M5 (vertical)
    set m5pwrwidth        [expr 0.096 * (5 + (4 * 1))]
    set m5pwrset2settracks 320
    set m5pwrset2setdist   [expr $m5pwrset2settracks * 0.192]
    set m5pwrspacing       [expr 0.096 * 21]
    set m5pwrxoffset       [expr (0.096 * 70) + 0.024]
    print "M5 PWR width/set2set/spacing/offset: $m5pwrwidth $m5pwrset2setdist $m5pwrspacing $m5pwrxoffset"
    setAddStripeMode -stacked_via_bottom_layer M4 -stacked_via_top_layer M5
    setViaGenMode -bar_cut_orientation horizontal
    addStripe -extend_to design_boundary \
        -direction vertical \
        -skip_via_on_wire_shape Noshape \
        -max_same_layer_jog_length 0.32 \
        -set_to_set_distance $m5pwrset2setdist \
        -skip_via_on_pin Standardcell \
        -spacing $m5pwrspacing \
        -start_offset $m5pwrxoffset \
        -merge_stripes_value 0.16 \
        -layer M5 \
        -width $m5pwrwidth \
        -nets {VDD VSS}

    # 6.5.3 : M6 (horizontal)
    set m6pwrwidth        [expr 0.128 * (5 + (4 * 1))]
    set m6pwrset2settracks 220
    set m6pwrset2setdist   [expr $m6pwrset2settracks * 0.256]
    set m6pwrspacing       [expr 0.128 * 21]
    set m6pwrxoffset       [expr (0.128 * 50) + 0.008]
    print "M6 PWR width/set2set/spacing/offset: $m6pwrwidth $m6pwrset2setdist $m6pwrspacing $m6pwrxoffset"
    setAddStripeMode -stacked_via_bottom_layer M5 -stacked_via_top_layer M6
    setViaGenMode -bar_cut_orientation vertical
    addStripe -extend_to design_boundary \
        -direction horizontal \
        -skip_via_on_wire_shape Noshape \
        -max_same_layer_jog_length 0.32 \
        -set_to_set_distance $m6pwrset2setdist \
        -skip_via_on_pin Standardcell \
        -spacing $m6pwrspacing \
        -start_offset $m6pwrxoffset \
        -merge_stripes_value 0.16 \
        -layer M6 \
        -width $m6pwrwidth \
        -nets {VDD VSS}
}


write_db $CKPT_DIR/02_power_plan.db
puts "INFO: power planning done"



### 7.  PLACEMENT + PRE-CTS OPT
place_opt_design

set_db add_tieoffs_cells      {TIEHIx1_ASAP7_75t_R TIELOx1_ASAP7_75t_R}
set_db add_tieoffs_max_fanout 8
if {[catch {add_tieoffs} err]} { puts "WARN: add_tieoffs skipped: $err" }

write_db $CKPT_DIR/03_place.db
puts "INFO: place_opt_design done"



### 8. CLOCK TREE SYNTHESIS
set_db cts_target_skew                $CTS_TARGET_SKEW
set_db cts_target_max_transition_time $CTS_TARGET_MAX_TRANS

set_db cts_inverter_cells {
    CKINVDCx5p33_ASAP7_75t_R CKINVDCx6p67_ASAP7_75t_R CKINVDCx8_ASAP7_75t_R
    CKINVDCx9p33_ASAP7_75t_R CKINVDCx10_ASAP7_75t_R  CKINVDCx11_ASAP7_75t_R
    CKINVDCx12_ASAP7_75t_R   CKINVDCx14_ASAP7_75t_R  CKINVDCx16_ASAP7_75t_R
    CKINVDCx20_ASAP7_75t_R
}
set_db cts_buffer_cells {
    BUFx2_ASAP7_75t_R  BUFx3_ASAP7_75t_R  BUFx4_ASAP7_75t_R  BUFx5_ASAP7_75t_R
    BUFx8_ASAP7_75t_R  BUFx10_ASAP7_75t_R BUFx12_ASAP7_75t_R BUFx24_ASAP7_75t_R
}

# Clock nets on [M4, M6], like the ASU reference's
# ccopt_route_group
create_route_type -name clk_route \
    -bottom_preferred_layer M4 -top_preferred_layer M6
set_db cts_route_type_top   clk_route
set_db cts_route_type_trunk clk_route
set_db cts_route_type_leaf  clk_route

create_clock_tree_spec
clock_opt_design

write_db $CKPT_DIR/04_cts.db
puts "INFO: clock_opt_design done"



### 9.  ROUTING  [M2, M7]
eval_legacy {
    setNanoRouteMode -routeDesignFixClockNets true
}
set_db route_with_si_driven     true
set_db route_with_timing_driven true

# Keep detail routing going until it stops improving
set_db route_detail_auto_stop false

# Diagnostic only: no routed net should exceed M7
catch {report_route_type_constraints -summary -out_file ${RPT_PFX}_route_types.rpt}

route_design

write_db $CKPT_DIR/05_route.db
puts "INFO: route_design done"



### 10. POST-ROUTE OPT
opt_design -post_route -setup
opt_design -post_route -hold

write_db $CKPT_DIR/06_post_route.db
puts "INFO: post-route optimization done"



### 11.  DECAP AND FILLER (ASU recipe order)
eval_legacy {
    addFiller -cell {DECAPx10_ASAP7_75t_R} -prefix FILLER_DECAP_
    addFiller -cell {DECAPx6_ASAP7_75t_R}  -prefix FILLER_DECAP_
    addFiller -cell {DECAPx4_ASAP7_75t_R}  -prefix FILLER_DECAP_
    addFiller -cell {TAPCELL_ASAP7_75t_R}  -prefix FILLER_TAP_
    addFiller -cell {FILLER_ASAP7_75t_R FILLERxp5_ASAP7_75t_R} -prefix FILLER_
}



### 12.  DRC REPAIR + CHECKS
check_drc -limit 0 -out_file ${RPT_PFX}_drc_pre_eco.rpt
summarize_drc ${RPT_PFX}_drc_pre_eco.rpt ${RPT_PFX}_drc_pre_eco_summary.rpt
if {[catch {route_eco -fix_drc} err]} { puts "WARN: route_eco skipped: $err" }

check_drc -limit 0 -out_file ${RPT_PFX}_drc.rpt
summarize_drc ${RPT_PFX}_drc.rpt ${RPT_PFX}_drc_summary.rpt
# Signal and PG connectivity reported separately: the PG report's dangling
# M3/M4 stubs at the die edge come from stripes extended to the boundary
# and are electrically harmless. The signal report is the one that matters.
check_connectivity -type regular -out_file ${RPT_PFX}_connectivity.rpt
check_connectivity -type special -out_file ${RPT_PFX}_connectivity_pg.rpt
check_place ${RPT_PFX}_place_check.rpt

write_db $CKPT_DIR/07_final.db
puts "INFO: checks done"



### 13. REPORTS
set_db timing_enable_simultaneous_setup_hold_mode true

report_area -detail -out_file ${RPT_PFX}_area.rpt

report_timing -check_type setup -max_paths 200 -nworst 20 \
    -path_type full_clock -nets  > ${RPT_PFX}_timing.rpt
report_timing -check_type hold  -max_paths 200 -nworst 20 \
    -path_type full_clock -nets >> ${RPT_PFX}_timing.rpt
report_timing_summary           >> ${RPT_PFX}_timing.rpt

report_power -view $SETUP_VIEW -out_file ${RPT_PFX}_power.rpt

report_timing_summary  >  ${RPT_PFX}_qor.rpt
report_area            >> ${RPT_PFX}_qor.rpt

puts "INFO: reports written to ${RPT_DIR}/ (prefix ${DESIGN}_${TAG})"



# 14. OUTPUTS
write_netlist -top_module $DESIGN ${OUT_PFX}_final.vh
write_def     -routing                ${OUT_PFX}.def
write_sdf     -max_view $SETUP_VIEW -min_view $HOLD_VIEW -version 3.0 \
              ${OUT_PFX}.sdf

puts ""
puts "── PnR done: ${freq} GHz, ${TAG}, corner ${pnr_corner} ──"
puts "  reports : ${RPT_DIR}/${DESIGN}_${TAG}_*.rpt"
puts "  outputs : ${OUT_DIR}/${DESIGN}_${TAG}_{final.vh,.def,.sdf}"



exit
