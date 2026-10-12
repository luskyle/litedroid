.PHONY: test check

check:
	bash -n scripts/litedroid tests/workflow.sh

test: check
	bash tests/workflow.sh
