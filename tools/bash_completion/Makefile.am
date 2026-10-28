EXTRA_DIST = lsmcli test_completion.sh test_sim_completion.sh

if WITH_BASH_COMPLETION
bashcompletion_DATA = lsmcli
# test_sim_completion.sh skips itself when the simulator plugin or the Python
# bindings were not built.
if WITH_TEST
TESTS = test_completion.sh test_sim_completion.sh
endif
endif
