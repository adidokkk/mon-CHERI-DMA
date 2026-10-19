#!/usr/bin/env bash

###########################################################################
## patch_asap7_lef.sh 
##
## Fix the malformed cut-enclosure rules in the ASAP7
## 4x-scaled technology LEF.
#############################################################################

#                                  PROBLEM:
#   asap7_tech_4x_201209.lef states the single-cut enclosure rules as, e.g.
#       ENCLOSURE CUTCLASS V3 BELOW EOL 0.0 0.020 0.0 ;
#       ENCLOSURE CUTCLASS V3 ABOVE EOL 0.0 0.044 0.0 ;
#   The EOL form takes  EOL <eolWidth> <eolOverhang> <otherOverhang>, and the
#   eolWidth here is 0.0, so no wire edge ever qualifies as an end-of-line.
#   Innovus 25.10 flags this (NRDB-2012) and then reports an enclosure
#   violation on essentially every single-cut V3/V5 via, even though the
#   LEF's own default vias satisfy the rule the author intended.
#
#                                     FIX:
#   Rewrite every  "... EOL <w> <eolOvh> <otherOvh>;"  enclosure line as:
#                  "... END <eolOvh> SIDE <otherOvh>;"
#   which is what the geometry implements and what Innovus checks correctly.
#   Nothing else in the file is touched, and the original is never modified:
#   a patched copy is written in the project directory and sourced by 
#   `asap7_setup.tcl`.
#

# Usage:
#   ./patch_asap7_lef.sh [src_lef] [dst_lef] [form={geom, end_side, overhang}]
#       • geom (default) – geometry-correct END/SIDE assignment:
#           BELOW -> "END <eolOvh> SIDE <otherOvh>"
#           ABOVE -> "END <otherOvh> SIDE <eolOvh>"
#       • end_side       – "END <eolOvh> SIDE <otherOvh>" for both
#       • overhang       – "<otherOvh> <eolOvh>"
# Defaults:
#   src   = $ASAP7_ROOT/asap7sc7p5t_28/techlef_misc/asap7_tech_4x_201209.lef
#   dst   = ./lef/asap7_tech_4x_201209_patched.lef
#   form  = geom

set -euo pipefail

ASAP7_ROOT="${ASAP7_ROOT:-$HOME/pdk/asap7}"
SRC="${1:-$ASAP7_ROOT/asap7sc7p5t_28/techlef_misc/asap7_tech_4x_201209.lef}"
DST="${2:-./lef/asap7_tech_4x_201209_patched.lef}"
FORM="${3:-geom}"
case "$FORM" in geom|end_side|overhang) ;; *) echo "ERROR: form must be end_side or overhang" >&2; exit 1;; esac

[ -f "$SRC" ] || { echo "ERROR: source LEF not found: $SRC" >&2; exit 1; }
mkdir -p "$(dirname "$DST")"

# Only lines whose eolWidth is 0 (unusable) are converted,
# while a real EOL rule with a nonzero width is left alone.
if [ "$FORM" = "geom" ]; then
  perl -pe '
    s{^(\s*ENCLOSURE\b[^;]*?\bBELOW\s+)EOL\s+0(?:\.0+)?\s+([0-9.]+)\s+([0-9.]+)\s*;}
     {$1END $2 SIDE $3 ;}x;
    s{^(\s*ENCLOSURE\b[^;]*?\bABOVE\s+)EOL\s+0(?:\.0+)?\s+([0-9.]+)\s+([0-9.]+)\s*;}
     {$1END $3 SIDE $2 ;}x;
    s{^(\s*)ENCLOSURE\s+CUTCLASS\s+(\S+)\s+EOL\s+0(?:\.0+)?\s+([0-9.]+)\s+([0-9.]+)\s*;}
     {$1ENCLOSURE CUTCLASS $2 BELOW END $3 SIDE 0.0 ;\n$1ENCLOSURE CUTCLASS $2 ABOVE END 0.0 SIDE $4 ;}x;
  ' "$SRC" > "$DST"
elif [ "$FORM" = "end_side" ]; then
  perl -pe '
    s{^(\s*ENCLOSURE\b[^;]*?)\bEOL\s+0(?:\.0+)?\s+([0-9.]+)\s+([0-9.]+)\s*;}
     {$1END $2 SIDE $3 ;}x
  ' "$SRC" > "$DST"
else
  perl -pe '
    s{^(\s*ENCLOSURE\b[^;]*?)\bEOL\s+0(?:\.0+)?\s+([0-9.]+)\s+([0-9.]+)\s*;}
     {$1$3 $2 ;}x
  ' "$SRC" > "$DST"
fi

echo "form: $FORM"
echo "##### converted lines (old to new) #####"
diff <(grep -nE "ENCLOSURE.*EOL" "$SRC" || true) \
     <(grep -nE "ENCLOSURE.*(EOL|END .* SIDE)" "$DST" || true) || true
echo
echo "##### remaining EOL-form enclosure rules in patched file (should be none with eolWidth 0) #####"
grep -nE "ENCLOSURE.*EOL" "$DST" || echo "  (none)"
echo
echo "patched LEF written to: $DST"
echo "next: ensure asap7_setup.tcl picks it up, then re-run PnR from scratch."
