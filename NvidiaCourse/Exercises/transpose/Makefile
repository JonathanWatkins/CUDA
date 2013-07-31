include ../cuda.mk

CUPPFLAGS += -I./include
CPPFLAGS  += -I./include

UTILS = utils/cutil.o utils/bank_checker.o utils/stopwatch.o utils/stopwatch_linux.o utils/cmd_arg_reader.o

transpose: transpose.o transpose_gold.o $(UTILS)
	$(LINK.cu) $^ $(CULOADLIBES) $(CULDLIBS) -o $@

clean:
	$(RM) transpose.o transpose_gold.o transpose $(UTILS)
