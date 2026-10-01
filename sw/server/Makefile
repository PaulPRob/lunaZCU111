# lunaserver Makefile
#
#   make            cross-compile for the ZCU111 (needs librfdc + libmetal in
#                   the sysroot: SYSROOT=<petalinux sdk sysroot>)
#   make host       native build without RFDC support (simulation / tests)
#   make cross-norfdc  aarch64 build without RFDC (compile check)
#
# In PetaLinux the recipe sw/petalinux/.../lunaserver builds this directly.

SRCS    = main.c hw.c clocks.c rfdc_init.c pl.c config.c net.c sim.c
HDRS    = $(wildcard *.h)
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter
LDLIBS  = -lm

CROSS   ?= aarch64-linux-gnu-
TARGET_CC ?= $(CROSS)gcc
SYSROOT ?=

ifneq ($(SYSROOT),)
SYSFLAGS = --sysroot=$(SYSROOT)
endif

all: lunaserver

lunaserver: $(SRCS) $(HDRS)
	$(TARGET_CC) $(SYSFLAGS) $(CFLAGS) -o $@ $(SRCS) $(LDFLAGS) -lrfdc -lmetal $(LDLIBS)

host: lunaserver-host
lunaserver-host: $(SRCS) $(HDRS)
	gcc $(CFLAGS) -DLUNA_NO_RFDC -o $@ $(SRCS) $(LDLIBS)

cross-norfdc: lunaserver-norfdc
lunaserver-norfdc: $(SRCS) $(HDRS)
	$(TARGET_CC) $(CFLAGS) -DLUNA_NO_RFDC -o $@ $(SRCS) $(LDLIBS)

# regenerate clk_tables.h from the TICS Pro files (the header is committed)
tables:
	python3 gen_clk_tables.py clk_tables/ZCU111_RevA_01132018_U90_122.88MHz.txt \
	    clk_tables/ZCU111_RevA_24102018_U102_103_104__LMX2594_245.76MHz.txt > clk_tables.h

install: lunaserver
	install -D -m 0755 lunaserver $(DESTDIR)/usr/bin/lunaserver

clean:
	rm -f lunaserver lunaserver-host lunaserver-norfdc

.PHONY: all host cross-norfdc install clean tables
