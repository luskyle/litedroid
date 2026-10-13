.PHONY: test check

check:
	bash -n scripts/litedroid scripts/cuttlefish-host-setup scripts/cuttlefish-bazel scripts/cuttlefish-curl tests/workflow.sh

test: check
	bash tests/workflow.sh
