wtest:
ifeq ($(dir),)
	echo "You must specify the package directory for this command."
else
	cd $(dir) && $(MAKE) wtest
endif

wtest-api: 
	$(MAKE) wtest dir=cascade-api

.PHONY: wtest wtest-api
