# vim: set noexpandtab:
CUDA = /usr/local/cuda-5.0

# Variables
CUCC        = nvcc
CUPPFLAGS   = -I$(CUDA)/include -I.
CUFLAGS     =
CULOADLIBES = -L$(CUDA)/lib64
CULDLIBS    = -lcuda -lcudart
CULDFLAGS   =

# Macros for compiling and linking
COMPILE.cu = $(CUCC) $(CUPPFLAGS) $(CUFLAGS)
LINK.cu    = $(CUCC) $(CUPPFLAGS) $(CUFLAGS) $(CULDFLAGS)

# CUDA rules
%.o: %.cu
	$(COMPILE.cu) -c $<

%: %.cu
	$(LINK.cu) $^ $(CULOADLIBES) $(CULDLIBS) -o $@
