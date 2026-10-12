# Include after all vendor/product inheritance in the board product makefile.
include vendor/litedroid/config.mk

LITEDROID_PROFILE := minimal
PRODUCT_PACKAGES := $(filter-out $(LITEDROID_REMOVE_PACKAGES),$(PRODUCT_PACKAGES))
