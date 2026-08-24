# Determine the location of the root of the repository
export GRASP := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# If present, load the Make.user file which may contain user-defined overrides
# to environment variables.
MAKE_USER_FILE := $(GRASP)/Make.user
ifeq (exists, $(shell [ -e $(MAKE_USER_FILE) ] && echo exists ))
include $(MAKE_USER_FILE)
endif

# Variables affecting the GRASP build. These can be overridden in Make.user or via
# environment variables.
export FC ?= gfortran
export FC_FLAGS ?= -O2 -fno-automatic
export FC_LD ?=
export FC_MPI ?= mpifort
export LAPACK_LIBS ?= -llapack -lblas
export FC_MPIFLAGS ?= $(FC_FLAGS)
export FC_MPILD ?= $(FC_LD)

LIBRARIES = libmod lib9290 libdvd90 mpi90
APPLICATIONS = rmcdhf90 rmcdhf90_mem rmcdhf90_mpi rmcdhf90_mem_mpi

LIBRARY_TARGETS = $(foreach library,$(LIBRARIES),src/lib/$(library))
APPLICATION_TARGETS = $(foreach application,$(APPLICATIONS),src/appl/$(application))

.PHONY: all lib appl $(LIBRARY_TARGETS) $(APPLICATION_TARGETS)
all: lib appl
appl: $(APPLICATION_TARGETS)
lib: $(LIBRARY_TARGETS)
$(LIBRARY_TARGETS): src/lib/%:
	@echo "Building: $@"
	$(MAKE) -C $@
$(APPLICATION_TARGETS): src/appl/%: lib
	@echo "Building: $@"
	$(MAKE) -C $@
LIBRARY_CLEAN_TARGETS = $(foreach library,$(LIBRARIES),clean/lib/$(library))
APPLICATION_CLEAN_TARGETS = $(foreach application,$(APPLICATIONS),clean/appl/$(application))
.PHONY: clean cleanall clean/lib clean/appl $(LIBRARY_CLEAN_TARGETS) $(APPLICATION_CLEAN_TARGETS)
clean: clean/lib clean/appl $(LIBRARY_CLEAN_TARGETS) $(APPLICATION_CLEAN_TARGETS)
cleanall: clean/lib clean/appl clean/exec $(LIBRARY_CLEAN_TARGETS) $(APPLICATION_CLEAN_TARGETS)
clean/lib: $(LIBRARY_CLEAN_TARGETS)
$(LIBRARY_CLEAN_TARGETS): clean/lib/%:
	$(MAKE) -C src/lib/$* clean
clean/appl: $(APPLICATION_CLEAN_TARGETS)
clean/exec:
	rm -vf $(GRASP)/bin/*
	rm -vf $(GRASP)/lib/*.a
$(APPLICATION_CLEAN_TARGETS): clean/appl/%:
	$(MAKE) -C src/appl/$* clean
