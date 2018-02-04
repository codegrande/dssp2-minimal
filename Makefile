# -*- Mode: makefile; indent-tabs-mode: t -*-
# SPDX-License-Identifier: Unlicense

.PHONY: all clean policy install-config install-semodule

include build.conf

BINDIR ?= /bin
DESTDIR ?= /
FIND = $(USRBINDIR)/find
INSTALL = $(USRBINDIR)/install
MKDIR = $(BINDIR)/mkdir
RM = $(BINDIR)/rm
SBINDIR ?= /sbin
SEMODULE = $(USRSBINDIR)/semodule
SHAREDSTATEDIR ?= /var/lib
SYSCONFDIR ?= /etc
USRBINDIR ?= /usr/bin
USRSBINDIR ?= /usr/sbin

MODULES = $(shell $(FIND) . -name *.cil -print)

ifdef TEST_TOOLCHAIN
tc_usrbindir := env LD_LIBRARY_PATH="$(TEST_TOOLCHAIN)/lib:$(TEST_TOOLCHAIN)/usr/lib" $(TEST_TOOLCHAIN)$(USRBINDIR)
else
tc_usrbindir := $(USRBINDIR)
endif

SECILC ?= $(tc_usrbindir)/secilc

all: clean policy.$(POLICY_VERSION)

clean:
	$(RM) -f policy.$(POLICY_VERSION) file_contexts

$(POLICY_VERSION): $(MODULES)
	$(SECILC) -v --policyvers=$(POLICY_VERSION) --o="$@" $^

policy.%: $(MODULES)
	$(SECILC) -v --policyvers=$* --o="$@" $^

install-config:
	$(MKDIR) -p $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/files
	$(MKDIR) -p $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/users
	$(MKDIR) -p $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/logins
	$(INSTALL) -m0644 config/customizable_types $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/customizable_types
	$(INSTALL) -m0644 config/dbus_contexts $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/dbus_contexts
	$(INSTALL) -m0644 config/default_contexts $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/default_contexts
	$(INSTALL) -m0644 config/default_type $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/default_type
	$(INSTALL) -m0644 config/failsafe_context $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/failsafe_context
	$(INSTALL) -m0644 config/file_contexts.subs_dist $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/files/file_contexts.subs_dist
	$(INSTALL) -m0644 config/media $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/files/media
	$(INSTALL) -m0644 config/openssh_contexts $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/openssh_contexts
	$(INSTALL) -m0644 config/x_contexts $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/x_contexts
	$(INSTALL) -m0644 config/removable_context $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/removable_context
	$(INSTALL) -m0644 config/securetty_types $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/securetty_types
	$(INSTALL) -m0644 config/virtual_domain_context $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/virtual_domain_context
	$(INSTALL) -m0644 config/virtual_image_context $(DESTDIR)/$(SYSCONFDIR)/selinux/$(POLICY_NAME)/contexts/virtual_image_context

install-semodule: install-config
	$(MKDIR) -p $(DESTDIR)/$(SHAREDSTATEDIR)/selinux/$(POLICY_NAME)
	$(SEMODULE) --priority=100 -i $(MODULES) -N -s $(POLICY_NAME) -p $(DESTDIR)
