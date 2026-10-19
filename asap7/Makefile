##################################################################################################
## Makefile
##
## Author: Giovanni Sirtori <gs86@rice.edu>
##
## Description: Drives Genus synthesis and Innovus P&R
## across a frequency sweep × {base, cheri} for the mCD design.
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

#	Usage:
#		make all                  	# syn then pnr, all freqs × {base,cheri}
#		make syn                  	# synthesis only
#		make pnr                  	# P&R only (requires syn outputs to exist)
#		make syn FREQS="1.0 1.5"	# custom freq list
#    	make syn-1.2__1           	# single point: 1.2 GHz, CHERI_EN=1
#    	make pnr-1.2__1           	# single point P&R
#    	make full-1.2__1          	# single point: syn then pnr
#    	make clean                	# remove all freq_*/{syn,pnr}

GENUS         ?= /clear/apps/elec8/bin/genus-2025
INNOVUS       ?= /clear/apps/elec8/bin/innovus-2025
GENUS_FLAGS   ?= -overwrite -batch
INNOVUS_FLAGS ?= -stylus -no_gui -overwrite
SYN_TCL       := synth.tcl
PNR_TCL       := pnr.tcl

MIN_FREQ  ?= 2.05
STEP_FREQ ?= 0.01
MAX_FREQ  ?= 2.15

# Sweep space
FREQS  ?= $(sort $(shell seq $(MIN_FREQ) $(STEP_FREQ) $(MAX_FREQ)) $(MAX_FREQ))
CHERIS ?= 0 1

# Build "<freq>__<cheri>" combos (e.g. 1.2__0, 1.2__1, etc.)
COMBOS := $(foreach f,$(FREQS),$(foreach c,$(CHERIS),$(f)__$(c)))

.PHONY: all full syn pnr clean clean-syn clean-pnr

all:
	$(MAKE) syn
	$(MAKE) pnr

full: $(addprefix full-,$(COMBOS))

full-%:
	$(MAKE) syn-$*
	$(MAKE) pnr-$*

###	SYNTHESIS  ###
syn: $(addprefix syn-,$(COMBOS))

# Pattern rule: syn-<freq>__<cheri>
# freq/cheri are passed to the script via environment variables (FREQ/CHERI_EN)
syn-%:
	@F='$(word 1,$(subst __, ,$*))'; \
	 C='$(word 2,$(subst __, ,$*))'; \
	 if [ "$$C" = "1" ]; then T=CHERI; else T=BASE; fi; \
	 echo ">>> Synthesis: $$F GHz, CHERI_EN=$$C ($$T)"; \
	 mkdir -p freq_$$F/syn/reports freq_$$F/syn/outs; \
	 echo="2" | FREQ=$$F CHERI_EN=$$C $(GENUS) $(GENUS_FLAGS) \
	     -execute "set_db source_verbose false" \
	     -log freq_$$F/syn/genus_$$T \
	     -f $(SYN_TCL); \
	 rm -rf fv/; \
	 rm -f .*.tstamp; \
	 rm -f freq_$$F/syn/*.cmd

###  PLACE & ROUTE  ###
pnr: $(addprefix pnr-,$(COMBOS))

# Pattern rule: pnr-<freq>__<cheri>
# Consumes the matching synthesis netlist/SDC/area report, with
# FREQ/CHERI_EN passed by environment variables
pnr-%:
	@F='$(word 1,$(subst __, ,$*))'; \
	 C='$(word 2,$(subst __, ,$*))'; \
	 if [ "$$C" = "1" ]; then T=CHERI; else T=BASE; fi; \
	 if [ ! -f freq_$$F/syn/outs/mCD_$${T}_netlist.vh ]; then \
	     echo "ERROR: freq_$$F/syn/outs/mCD_$${T}_netlist.vh missing — run 'make syn' first"; \
	     exit 1; \
	 fi; \
	 echo ">>> PnR: $$F GHz, CHERI_EN=$$C ($$T)"; \
	 mkdir -p freq_$$F/pnr/reports freq_$$F/pnr/outs; \
	 echo="2" | FREQ=$$F CHERI_EN=$$C $(INNOVUS) $(INNOVUS_FLAGS) \
		 -execute "set_db source_verbose false" \
	     -log freq_$$F/pnr/innovus_$$T \
	     -files $(PNR_TCL); \
	 rm -rf timingReports/; \
	 rm -f *.bin voltus*.txt *.option *.cts.*; \
	 rm -f freq_$$F/pnr/*.cmd freq_$$F/pnr/*.logv freq_$$F/pnr/reports/.*metrics freq_$$F/pnr/reports/*.old


#  Cleanup
clean-syn:
	rm -rf freq_*/syn
clean-pnr:
	rm -rf freq_*/pnr
clean: clean-syn clean-pnr